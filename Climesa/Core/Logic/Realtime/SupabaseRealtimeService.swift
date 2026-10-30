import Foundation

private struct LoopState {
    var cursor = "0"
    var wasDown = false
    var failures = 0
    var hasCursor = false
}

private actor RefCounter {
    private var value = 0
    func next() -> String { value += 1; return String(value) }
}

/// Cliente mínimo del protocolo Phoenix de Supabase Realtime. Igual que web/src/lib/live.ts y que el repositorio
/// de Android: se une a los canales de /auth/me, emite los eventos y, solo tras una caída, hace UNA consulta de
/// recuperación a `/eventos?after=<seq>`. Los únicos temporizadores son el latido del protocolo y la espera
/// creciente entre reconexiones; eso no es sondeo de datos.
public struct SupabaseRealtimeService: RealtimeService {
    private let websocketURL: String
    private let accessToken: @Sendable () async -> String?
    private let catchUp: @Sendable (String) async throws -> CatchUp
    private let head: (@Sendable () async throws -> String)?
    private let pageSize: Int
    private let sockets: any RealtimeSocketFactory
    private let heartbeatInterval: TimeInterval
    private let backoff: @Sendable (Int) -> TimeInterval
    private let offlineAfterFailures: Int

    public init(
        websocketURL: String,
        accessToken: @escaping @Sendable () async -> String?,
        catchUp: @escaping @Sendable (String) async throws -> CatchUp,
        head: (@Sendable () async throws -> String)? = nil,
        pageSize: Int = 200,
        sockets: any RealtimeSocketFactory,
        heartbeatInterval: TimeInterval = 25,
        backoff: @escaping @Sendable (Int) -> TimeInterval = SupabaseRealtimeService.defaultBackoff,
        offlineAfterFailures: Int = 3
    ) {
        self.websocketURL = websocketURL
        self.accessToken = accessToken
        self.catchUp = catchUp
        self.head = head
        self.pageSize = pageSize
        self.sockets = sockets
        self.heartbeatInterval = heartbeatInterval
        self.backoff = backoff
        self.offlineAfterFailures = offlineAfterFailures
    }

    /// 1, 2, 4, 8, 16 y luego 30 segundos como máximo.
    public static func defaultBackoff(_ attempt: Int) -> TimeInterval {
        min(30, pow(2, Double(min(max(attempt - 1, 0), 5))))
    }

    public func observe(channels: [String]) -> AsyncStream<RealtimeSignal> {
        AsyncStream(RealtimeSignal.self) { continuation in
            let task = Task { await self.run(channels: channels, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func connectionState(failures: Int) -> ConnectionState {
        failures >= offlineAfterFailures ? .offline : .reconnecting
    }

    private static func pause(_ seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    private func run(channels: [String], continuation: AsyncStream<RealtimeSignal>.Continuation) async {
        var progress = LoopState()
        while !Task.isCancelled {
            continuation.yield(.state(connectionState(failures: progress.failures)))
            guard let token = await accessToken() else {
                progress.failures += 1
                progress.wasDown = true
                let resumed = await Self.pause(backoff(progress.failures))
                if !resumed { break }
                continue
            }
            let socket = sockets.open(url: websocketURL)
            await drive(socket: socket, token: token, channels: channels, progress: &progress, continuation: continuation)
            socket.close()
            if Task.isCancelled { break }
            progress.wasDown = true
            progress.failures += 1
            continuation.yield(.state(connectionState(failures: progress.failures)))
            let resumed = await Self.pause(backoff(progress.failures))
            if !resumed { break }
        }
        continuation.finish()
    }

    /// Atiende un socket hasta que se cae, el servidor cierra un canal o se cancela la tarea.
    private func drive(
        socket: any RealtimeSocket,
        token: String,
        channels: [String],
        progress: inout LoopState,
        continuation: AsyncStream<RealtimeSignal>.Continuation
    ) async {
        let refs = RefCounter()
        let interval = heartbeatInterval
        var joined = Set<String>()
        var heartbeat: Task<Void, Never>?
        loop: for await event in socket.events {
            switch event {
            case .opened:
                for channel in channels {
                    let ref = await refs.next()
                    _ = await socket.send(RealtimeProtocol.join(channel: channel, ref: ref, accessToken: token))
                }
                heartbeat = Task {
                    while !Task.isCancelled {
                        let resumed = await SupabaseRealtimeService.pause(interval)
                        if !resumed { return }
                        let ref = await refs.next()
                        _ = await socket.send(RealtimeProtocol.heartbeat(ref: ref))
                    }
                }
            case .closed:
                break loop
            case .text(let text):
                switch RealtimeProtocol.parse(text) {
                case .joinReply(let channel, let ok):
                    if !ok { break loop }
                    if joined.insert(channel).inserted && joined.count == channels.count {
                        progress.failures = 0
                        if progress.wasDown && (progress.hasCursor || head == nil) {
                            do {
                                // Una consulta por reconexión; si la página viene llena, se pide la siguiente.
                                var more = true
                                while more {
                                    let previous = progress.cursor
                                    let recovered = try await catchUp(previous)
                                    progress.cursor = recovered.cursor
                                    progress.hasCursor = true
                                    for recoveredEvent in recovered.events { continuation.yield(.event(recoveredEvent)) }
                                    more = recovered.events.count >= pageSize && recovered.cursor != previous
                                }
                                progress.wasDown = false
                            } catch {
                                break loop
                            }
                        } else if !progress.hasCursor, let head {
                            // Primera unión (o caída antes de tener cursor): se guarda el cursor actual del servidor.
                            // La resincronización completa que sigue cubre lo que pudo perderse.
                            if let current = try? await head() {
                                progress.cursor = current
                                progress.hasCursor = true
                                progress.wasDown = false
                            }
                        }
                        continuation.yield(.resync)
                        continuation.yield(.state(.live))
                    }
                case .broadcast(_, let domainEvent):
                    continuation.yield(.event(domainEvent))
                case .channelClosed:
                    break loop
                case .ignored:
                    break
                }
            }
        }
        heartbeat?.cancel()
    }
}
