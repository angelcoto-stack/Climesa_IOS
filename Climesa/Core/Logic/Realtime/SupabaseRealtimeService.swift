import Foundation

private struct LoopState {
    var cursor = "0"
    var wasDown = false
    var failures = 0
    var hasCursor = false
    /// Rechazos seguidos por canal; se reinicia cuando el canal se une bien.
    var rejections: [String: Int] = [:]
    /// Canales dejados fuera tras demasiados rechazos seguidos.
    var dropped = Set<String>()
    /// Ya se avisó "en vivo" en el socket actual.
    var liveReported = false
}

/// Estado compartido entre la lectura de eventos y el latido de un mismo socket.
private actor SocketSession {
    private var counter = 0
    private var pendingRef: String?
    private var joined = Set<String>()
    private var token: String

    init(token: String) { self.token = token }

    func nextRef() -> String { counter += 1; return String(counter) }
    func expectReply(_ ref: String) { pendingRef = ref }
    func acknowledge(_ ref: String) { if pendingRef == ref { pendingRef = nil } }
    func isWaiting(for ref: String) -> Bool { pendingRef == ref }
    func markJoined(_ channel: String) -> Bool { joined.insert(channel).inserted }
    func isJoined(_ channel: String) -> Bool { joined.contains(channel) }
    func joinedChannels() -> [String] { joined.sorted() }

    func hasJoinedAll(_ needed: [String]) -> Bool {
        for channel in needed where !joined.contains(channel) { return false }
        return true
    }

    /// Devuelve true si el token cambió respecto al que usa este socket.
    func renewToken(_ fresh: String) -> Bool {
        if fresh == token { return false }
        token = fresh
        return true
    }
}

/// Cliente mínimo del protocolo Phoenix de Supabase Realtime. Igual que web/src/lib/live.ts y que el repositorio
/// de Android: se une a los canales de /auth/me, emite los eventos y, solo tras una caída, hace UNA consulta de
/// recuperación a `/eventos?after=<seq>`. Los únicos temporizadores son el latido del protocolo y la espera
/// creciente entre reconexiones; eso no es sondeo de datos.
///
/// - El latido espera su `phx_reply`; sin respuesta en `heartbeatTimeout` el socket se da por caído y se reconecta.
/// - En cada latido se consulta el token de la sesión; si cambió, se manda `access_token` a los canales unidos.
/// - Un canal rechazado `maxJoinRejections` veces seguidas se deja fuera y el resto sigue en vivo, con un aviso no fatal.
public struct SupabaseRealtimeService: RealtimeService {
    private let websocketURL: String
    private let accessToken: @Sendable () async -> String?
    private let catchUp: @Sendable (String) async throws -> CatchUp
    private let head: (@Sendable () async throws -> String)?
    private let pageSize: Int
    private let sockets: any RealtimeSocketFactory
    private let heartbeatInterval: TimeInterval
    private let heartbeatTimeout: TimeInterval
    private let backoff: @Sendable (Int) -> TimeInterval
    private let offlineAfterFailures: Int
    private let maxJoinRejections: Int

    public init(
        websocketURL: String,
        accessToken: @escaping @Sendable () async -> String?,
        catchUp: @escaping @Sendable (String) async throws -> CatchUp,
        head: (@Sendable () async throws -> String)? = nil,
        pageSize: Int = 200,
        sockets: any RealtimeSocketFactory,
        heartbeatInterval: TimeInterval = 25,
        heartbeatTimeout: TimeInterval = 10,
        backoff: @escaping @Sendable (Int) -> TimeInterval = SupabaseRealtimeService.defaultBackoff,
        offlineAfterFailures: Int = 3,
        maxJoinRejections: Int = 3
    ) {
        self.websocketURL = websocketURL
        self.accessToken = accessToken
        self.catchUp = catchUp
        self.head = head
        self.pageSize = pageSize
        self.sockets = sockets
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        self.backoff = backoff
        self.offlineAfterFailures = offlineAfterFailures
        self.maxJoinRejections = maxJoinRejections
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
            let active = channels.filter { !progress.dropped.contains($0) }
            if active.isEmpty {
                // Todos los canales fueron rechazados: no hay nada que reintentar; se espera a que cancelen.
                continuation.yield(.state(.offline))
                while await Self.pause(3600) {}
                break
            }
            continuation.yield(.state(connectionState(failures: progress.failures)))
            guard let token = await accessToken() else {
                progress.failures += 1
                progress.wasDown = true
                let resumed = await Self.pause(backoff(progress.failures))
                if !resumed { break }
                continue
            }
            let socket = sockets.open(url: websocketURL)
            await drive(socket: socket, token: token, channels: active, progress: &progress, continuation: continuation)
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

    /// Latido del protocolo. Antes de cada latido renueva el token en los canales unidos si la sesión lo cambió, y
    /// tras enviarlo espera su respuesta; sin ella cierra el socket para que el servicio reconecte.
    private static func beat(
        socket: any RealtimeSocket,
        session: SocketSession,
        interval: TimeInterval,
        timeout: TimeInterval,
        accessToken: @Sendable () async -> String?
    ) async {
        while !Task.isCancelled {
            let resumed = await pause(interval)
            if !resumed { return }
            if let fresh = await accessToken() {
                let changed = await session.renewToken(fresh)
                if changed {
                    let joinedNow = await session.joinedChannels()
                    for channel in joinedNow {
                        let tokenRef = await session.nextRef()
                        _ = await socket.send(RealtimeProtocol.accessToken(channel: channel, ref: tokenRef, accessToken: fresh))
                    }
                }
            }
            let ref = await session.nextRef()
            await session.expectReply(ref)
            let sent = await socket.send(RealtimeProtocol.heartbeat(ref: ref))
            if !sent {
                socket.close()
                return
            }
            let waited = await pause(timeout)
            if !waited { return }
            let stillWaiting = await session.isWaiting(for: ref)
            if stillWaiting {
                socket.close()
                return
            }
        }
    }

    /// Cuando ya están unidos todos los canales que cuentan: recupera lo perdido (si hubo caída) y avisa "en vivo".
    /// Devuelve false si el socket debe descartarse (falló la recuperación).
    private func completeJoin(
        channels: [String],
        session: SocketSession,
        progress: inout LoopState,
        continuation: AsyncStream<RealtimeSignal>.Continuation
    ) async -> Bool {
        if progress.liveReported { return true }
        let droppedNow = progress.dropped
        let needed = channels.filter { !droppedNow.contains($0) }
        if needed.isEmpty { return true }
        let ready = await session.hasJoinedAll(needed)
        if !ready { return true }
        progress.liveReported = true
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
                return false
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
        return true
    }

    /// Atiende un socket hasta que se cae, el servidor cierra un canal o se cancela la tarea.
    private func drive(
        socket: any RealtimeSocket,
        token: String,
        channels: [String],
        progress: inout LoopState,
        continuation: AsyncStream<RealtimeSignal>.Continuation
    ) async {
        let session = SocketSession(token: token)
        progress.liveReported = false
        let interval = heartbeatInterval
        let timeout = heartbeatTimeout
        let tokenProvider = accessToken
        let maxRejections = maxJoinRejections
        var heartbeat: Task<Void, Never>?
        loop: for await event in socket.events {
            switch event {
            case .opened:
                for channel in channels {
                    let ref = await session.nextRef()
                    _ = await socket.send(RealtimeProtocol.join(channel: channel, ref: ref, accessToken: token))
                }
                heartbeat = Task {
                    await SupabaseRealtimeService.beat(
                        socket: socket,
                        session: session,
                        interval: interval,
                        timeout: timeout,
                        accessToken: tokenProvider
                    )
                }
            case .closed:
                break loop
            case .text(let text):
                switch RealtimeProtocol.parse(text) {
                case .joinReply(let channel, let ok):
                    if ok {
                        let inserted = await session.markJoined(channel)
                        if inserted {
                            progress.rejections[channel] = nil
                            let proceed = await completeJoin(channels: channels, session: session, progress: &progress, continuation: continuation)
                            if !proceed { break loop }
                        }
                    } else {
                        let alreadyJoined = await session.isJoined(channel)
                        // Rechazo en un canal ya unido (p. ej. token rechazado): se reconecta sin contarlo.
                        if alreadyJoined { break loop }
                        let count = (progress.rejections[channel] ?? 0) + 1
                        progress.rejections[channel] = count
                        if count < maxRejections { break loop }
                        progress.dropped.insert(channel)
                        continuation.yield(.channelsDropped(progress.dropped))
                        let droppedNow = progress.dropped
                        let everyoneDropped = channels.allSatisfy { droppedNow.contains($0) }
                        if everyoneDropped { break loop }
                        let proceed = await completeJoin(channels: channels, session: session, progress: &progress, continuation: continuation)
                        if !proceed { break loop }
                    }
                case .heartbeatReply(let ref):
                    await session.acknowledge(ref)
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
