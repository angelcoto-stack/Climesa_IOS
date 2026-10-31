import XCTest
@testable import ClimesaCore

/// Doble de prueba del socket: guarda lo que se envía y deja empujar eventos a mano.
private final class FakeSocket: RealtimeSocket, @unchecked Sendable {
    let events: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation
    private let lock = NSLock()
    private var storedSent: [String] = []
    private var storedClosed = false

    init() {
        var captured: AsyncStream<SocketEvent>.Continuation?
        events = AsyncStream(SocketEvent.self) { captured = $0 }
        continuation = captured!
    }

    private func record(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        storedSent.append(text)
    }

    var sent: [String] { lock.lock(); defer { lock.unlock() }; return storedSent }
    var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return storedClosed }

    func send(_ text: String) async -> Bool { record(text); return true }

    func close() {
        lock.lock(); storedClosed = true; lock.unlock()
        continuation.finish()
    }

    func push(_ event: SocketEvent) { continuation.yield(event) }
}

private final class FakeSocketFactory: RealtimeSocketFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSockets: [FakeSocket] = []
    private let closeOnOpen: Bool

    init(closeOnOpen: Bool = false) { self.closeOnOpen = closeOnOpen }

    var sockets: [FakeSocket] { lock.lock(); defer { lock.unlock() }; return storedSockets }

    func open(url: String) -> RealtimeSocket {
        let socket = FakeSocket()
        socket.push(.opened)
        if closeOnOpen { socket.push(.closed("caída")) }
        lock.lock(); storedSockets.append(socket); lock.unlock()
        return socket
    }
}

private actor SignalRecorder {
    private(set) var signals: [RealtimeSignal] = []
    func add(_ signal: RealtimeSignal) { signals.append(signal) }
}

private actor CatchUpLog {
    private(set) var cursors: [String] = []
    func add(_ cursor: String) { cursors.append(cursor) }
}

private func joined(_ channel: String) -> String {
    #"{"topic":"realtime:\#(channel)","event":"phx_reply","payload":{"status":"ok"},"ref":"1"}"#
}

private func bedEvent(_ channel: String, _ id: String) -> String {
    #"{"topic":"realtime:\#(channel)","event":"broadcast","payload":{"event":"cama.estado_cambiado","type":"broadcast","payload":{"tipo":"cama.estado_cambiado","entidad":"cama","id":"\#(id)","version":2}}}"#
}

final class SupabaseRealtimeServiceTests: XCTestCase {
    private let channels = ["publico", "rol:ENF"]
    private let recovered = CatchUp(cursor: "9", events: [DomainEvent(type: "cama.estado_cambiado", entity: "cama", id: "perdida", version: 1)])

    private func makeService(
        _ factory: FakeSocketFactory,
        log: CatchUpLog,
        token: String? = "token-ejemplo",
        heartbeat: TimeInterval = 1_000,
        head: (@Sendable () async throws -> String)? = nil
    ) -> SupabaseRealtimeService {
        let recovered = self.recovered
        return SupabaseRealtimeService(
            websocketURL: "wss://ejemplo.test/socket",
            accessToken: { token },
            catchUp: { cursor in
                await log.add(cursor)
                return recovered
            },
            head: head,
            sockets: factory,
            heartbeatInterval: heartbeat,
            backoff: { _ in 0.01 }
        )
    }

    private func consume(_ service: SupabaseRealtimeService, into recorder: SignalRecorder) -> Task<Void, Never> {
        let channels = self.channels
        return Task {
            for await signal in service.observe(channels: channels) { await recorder.add(signal) }
        }
    }

    private func eventually(_ message: String, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail(message, file: file, line: line)
    }

    func testSeUneATodosLosCanalesYAvisaCuandoQuedaEnVivo() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe abrir un socket y enviar dos uniones") { factory.sockets.first?.sent.count == 2 }
        let socket = try XCTUnwrap(factory.sockets.first)
        socket.push(.text(joined("publico")))
        try await Task.sleep(nanoseconds: 50_000_000)
        let beforeAll = await recorder.signals
        XCTAssertFalse(beforeAll.contains(.resync), "con un solo canal unido aún no hay resincronización")

        socket.push(.text(joined("rol:ENF")))
        await eventually("debe resincronizar y quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }
        let signals = await recorder.signals
        XCTAssertTrue(signals.contains(.resync))
        let cursors = await log.cursors
        XCTAssertTrue(cursors.isEmpty, "sin caída previa no hay consulta de recuperación")
    }

    func testReenviaLosEventosDeLosCanales() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe abrir el socket") { factory.sockets.count == 1 }
        try XCTUnwrap(factory.sockets.first).push(.text(bedEvent("rol:ENF", "cama-1")))
        let esperado = RealtimeSignal.event(DomainEvent(type: "cama.estado_cambiado", entity: "cama", id: "cama-1", version: 2))
        await eventually("debe reenviar el evento") { await recorder.signals.contains(esperado) }
    }

    func testTrasUnaCaidaReconectaYHaceUnaSolaRecuperacion() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe abrir el primer socket") { factory.sockets.count == 1 }
        let first = try XCTUnwrap(factory.sockets.first)
        first.push(.text(joined("publico"))); first.push(.text(joined("rol:ENF")))
        await eventually("debe quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }

        first.push(.closed("red"))
        await eventually("debe abrir un segundo socket") { factory.sockets.count == 2 }
        let afterDrop = await recorder.signals
        XCTAssertTrue(afterDrop.contains(RealtimeSignal.state(.reconnecting)))

        let second = factory.sockets[1]
        second.push(.text(joined("publico"))); second.push(.text(joined("rol:ENF")))
        let perdido = RealtimeSignal.event(DomainEvent(type: "cama.estado_cambiado", entity: "cama", id: "perdida", version: 1))
        await eventually("debe emitir el evento recuperado") { await recorder.signals.contains(perdido) }
        await eventually("debe volver a quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }
        let cursors = await log.cursors
        XCTAssertEqual(cursors, ["0"])
        XCTAssertTrue(first.isClosed, "el primer socket se cerró")
    }

    func testConVariasCaidasSeguidasPasaASinConexion() async throws {
        let factory = FakeSocketFactory(closeOnOpen: true), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe llegar a sin conexión") { await recorder.signals.contains(RealtimeSignal.state(.offline)) }
        let cursors = await log.cursors
        XCTAssertTrue(cursors.isEmpty, "nunca se unió un canal, así que no hay recuperación")
    }

    func testSinTokenNoAbreSocketYReintenta() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log, token: nil), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe llegar a sin conexión") { await recorder.signals.contains(RealtimeSignal.state(.offline)) }
        XCTAssertTrue(factory.sockets.isEmpty)
    }

    func testEnviaElLatidoDelProtocoloAlAbrir() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log, heartbeat: 0.02), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe enviar al menos un latido") { factory.sockets.first?.sent.contains { $0.contains("\"heartbeat\"") } == true }
    }

    func testCancelarElConsumoCierraElSocket() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log), into: recorder)

        await eventually("debe abrir el socket") { factory.sockets.count == 1 }
        consumer.cancel()
        await eventually("debe cerrar el socket al cancelar") { factory.sockets.first?.isClosed == true }
    }

    func testLaEsperaEntreReconexionesCreceYTieneTope() {
        XCTAssertEqual(SupabaseRealtimeService.defaultBackoff(1), 1)
        XCTAssertEqual(SupabaseRealtimeService.defaultBackoff(2), 2)
        XCTAssertEqual(SupabaseRealtimeService.defaultBackoff(5), 16)
        XCTAssertEqual(SupabaseRealtimeService.defaultBackoff(6), 30)
        XCTAssertEqual(SupabaseRealtimeService.defaultBackoff(50), 30)
    }

    func testPrimeraUnionGuardaElCursorDelServidorYLaRecuperacionParteDeAhi() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log, head: { "7" }), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe abrir el primer socket") { factory.sockets.count == 1 }
        let first = try XCTUnwrap(factory.sockets.first)
        first.push(.text(joined("publico"))); first.push(.text(joined("rol:ENF")))
        await eventually("debe quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }

        first.push(.closed("red"))
        await eventually("debe abrir un segundo socket") { factory.sockets.count == 2 }
        let second = factory.sockets[1]
        second.push(.text(joined("publico"))); second.push(.text(joined("rol:ENF")))
        let perdido = RealtimeSignal.event(DomainEvent(type: "cama.estado_cambiado", entity: "cama", id: "perdida", version: 1))
        await eventually("debe emitir el evento recuperado") { await recorder.signals.contains(perdido) }
        let cursors = await log.cursors
        XCTAssertEqual(cursors, ["7"], "la recuperación parte del cursor guardado en la primera unión, no de 0")
    }

    func testPaginaLaRecuperacionMientrasLaPaginaVengaLlena() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let pageOne = CatchUp(cursor: "8", events: [DomainEvent(type: "turno.publicado", entity: "turno", id: "a", version: 1)])
        let pageTwo = CatchUp(cursor: "9", events: [])
        let service = SupabaseRealtimeService(
            websocketURL: "wss://ejemplo.test/socket",
            accessToken: { "token-ejemplo" },
            catchUp: { cursor in
                await log.add(cursor)
                return cursor == "7" ? pageOne : pageTwo
            },
            head: { "7" },
            pageSize: 1,
            sockets: factory,
            heartbeatInterval: 1_000,
            backoff: { _ in 0.01 }
        )
        let consumer = consume(service, into: recorder)
        defer { consumer.cancel() }

        await eventually("debe abrir el primer socket") { factory.sockets.count == 1 }
        let first = try XCTUnwrap(factory.sockets.first)
        first.push(.text(joined("publico"))); first.push(.text(joined("rol:ENF")))
        await eventually("debe quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }
        first.push(.closed("red"))
        await eventually("debe abrir un segundo socket") { factory.sockets.count == 2 }
        let second = factory.sockets[1]
        second.push(.text(joined("publico"))); second.push(.text(joined("rol:ENF")))
        await eventually("debe pedir la segunda página") { await log.cursors.count == 2 }
        let cursors = await log.cursors
        XCTAssertEqual(cursors, ["7", "8"])
    }

    // MARK: - Casos adicionales

    private func joinAll(_ socket: FakeSocket) {
        socket.push(.text(joined("publico")))
        socket.push(.text(joined("rol:ENF")))
    }

    /// Deja el servicio en vivo, cae el primer socket y une los canales del segundo; devuelve el segundo.
    private func dropAndRejoin(_ factory: FakeSocketFactory, _ recorder: SignalRecorder) async throws -> FakeSocket {
        await eventually("debe abrir el primer socket") { factory.sockets.count == 1 }
        let first = try XCTUnwrap(factory.sockets.first)
        joinAll(first)
        await eventually("debe quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }
        first.push(.closed("red"))
        await eventually("debe abrir un segundo socket") { factory.sockets.count == 2 }
        let second = factory.sockets[1]
        joinAll(second)
        return second
    }

    func testLaEsperaEntreReconexionesNuncaDecreceNiPasaDeTreintaSegundos() {
        XCTAssertEqual(SupabaseRealtimeService.defaultBackoff(0), 1)
        XCTAssertEqual(SupabaseRealtimeService.defaultBackoff(3), 4)
        XCTAssertEqual(SupabaseRealtimeService.defaultBackoff(4), 8)
        var previous: TimeInterval = 0
        for attempt in 1...40 {
            let wait: TimeInterval = SupabaseRealtimeService.defaultBackoff(attempt)
            XCTAssertGreaterThanOrEqual(wait, previous)
            XCTAssertLessThanOrEqual(wait, 30)
            previous = wait
        }
        XCTAssertEqual(previous, 30)
    }

    func testLaRecuperacionSeDetieneSiElCursorNoAvanza() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let service = SupabaseRealtimeService(
            websocketURL: "wss://ejemplo.test/socket",
            accessToken: { "token-ejemplo" },
            catchUp: { cursor in
                await log.add(cursor)
                return CatchUp(cursor: cursor, events: [DomainEvent(type: "turno.publicado", entity: "turno", id: "a", version: 1)])
            },
            head: { "7" },
            pageSize: 1,
            sockets: factory,
            heartbeatInterval: 1_000,
            backoff: { _ in 0.01 }
        )
        let consumer = consume(service, into: recorder)
        defer { consumer.cancel() }

        _ = try await dropAndRejoin(factory, recorder)
        let recuperado = RealtimeSignal.event(DomainEvent(type: "turno.publicado", entity: "turno", id: "a", version: 1))
        await eventually("debe emitir el evento recuperado") { await recorder.signals.contains(recuperado) }
        await eventually("debe volver a quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }
        let cursors = await log.cursors
        XCTAssertEqual(cursors, ["7"], "si el cursor no avanza no se vuelve a pedir")
    }

    func testLaRecuperacionTerminaAlLlegarUnaPaginaIncompleta() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let eventA = DomainEvent(type: "turno.publicado", entity: "turno", id: "a", version: 1)
        let eventB = DomainEvent(type: "turno.publicado", entity: "turno", id: "b", version: 1)
        let eventC = DomainEvent(type: "turno.publicado", entity: "turno", id: "c", version: 1)
        let service = SupabaseRealtimeService(
            websocketURL: "wss://ejemplo.test/socket",
            accessToken: { "token-ejemplo" },
            catchUp: { cursor in
                await log.add(cursor)
                if cursor == "7" { return CatchUp(cursor: "8", events: [eventA, eventB]) }
                return CatchUp(cursor: "9", events: [eventC])
            },
            head: { "7" },
            pageSize: 2,
            sockets: factory,
            heartbeatInterval: 1_000,
            backoff: { _ in 0.01 }
        )
        let consumer = consume(service, into: recorder)
        defer { consumer.cancel() }

        _ = try await dropAndRejoin(factory, recorder)
        await eventually("debe emitir el ultimo evento") { await recorder.signals.contains(RealtimeSignal.event(eventC)) }
        await eventually("debe volver a quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }
        let signals = await recorder.signals
        XCTAssertTrue(signals.contains(RealtimeSignal.event(eventA)))
        XCTAssertTrue(signals.contains(RealtimeSignal.event(eventB)))
        let cursors = await log.cursors
        XCTAssertEqual(cursors, ["7", "8"], "la segunda pagina trae menos de pageSize y ahi termina")
    }

    func testSiLaRecuperacionFallaElServicioReconectaYSigueVivo() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let service = SupabaseRealtimeService(
            websocketURL: "wss://ejemplo.test/socket",
            accessToken: { "token-ejemplo" },
            catchUp: { cursor in
                await log.add(cursor)
                throw TestFailure()
            },
            head: { "7" },
            sockets: factory,
            heartbeatInterval: 1_000,
            backoff: { _ in 0.01 }
        )
        let consumer = consume(service, into: recorder)
        defer { consumer.cancel() }

        let second = try await dropAndRejoin(factory, recorder)
        await eventually("debe abrir un tercer socket tras el fallo") { factory.sockets.count == 3 }
        XCTAssertTrue(second.isClosed, "el socket con la recuperacion fallida se cierra")
        let cursors = await log.cursors
        XCTAssertEqual(cursors, ["7"])
    }

    func testUnCanalRechazadoCierraElSocketYForzaUnaReconexion() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe abrir el primer socket") { factory.sockets.count == 1 }
        let first = try XCTUnwrap(factory.sockets.first)
        first.push(.text(joined("publico")))
        first.push(.text(#"{"topic":"realtime:rol:ENF","event":"phx_reply","payload":{"status":"error"},"ref":"2"}"#))
        await eventually("debe abrir un segundo socket") { factory.sockets.count >= 2 }
        XCTAssertTrue(first.isClosed)
        let signals = await recorder.signals
        XCTAssertFalse(signals.contains(RealtimeSignal.resync), "con un canal rechazado no se completa la union")
        XCTAssertFalse(signals.contains(RealtimeSignal.state(.live)))
    }

    func testIgnoraMarcosMalformadosDesconocidosYAcusesDeLatido() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let consumer = consume(makeService(factory, log: log), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe abrir el primer socket") { factory.sockets.count == 1 }
        let first = try XCTUnwrap(factory.sockets.first)
        first.push(.text("no es json"))
        first.push(.text(#"{"topic":"realtime:publico","event":"presence_state","payload":{}}"#))
        first.push(.text(#"{"topic":"phoenix","event":"phx_reply","payload":{"status":"ok"},"ref":"3"}"#))
        joinAll(first)
        await eventually("debe quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }
        XCTAssertEqual(factory.sockets.count, 1, "nada de lo anterior provoca una reconexion")
        XCTAssertFalse(first.isClosed)
    }

    func testCadaConexionPideUnTokenNuevoAlRenovarse() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder()
        let tokens = TokenSource()
        let service = SupabaseRealtimeService(
            websocketURL: "wss://ejemplo.test/socket",
            accessToken: { () async -> String? in await tokens.next() },
            catchUp: { _ in CatchUp(cursor: "0", events: []) },
            sockets: factory,
            heartbeatInterval: 1_000,
            backoff: { _ in 0.01 }
        )
        let consumer = consume(service, into: recorder)
        defer { consumer.cancel() }

        await eventually("debe enviar las dos uniones del primer socket") { factory.sockets.first?.sent.count == 2 }
        let first = try XCTUnwrap(factory.sockets.first)
        XCTAssertTrue(first.sent.allSatisfy { $0.contains("token-1") })
        first.push(.closed("red"))
        await eventually("debe enviar las dos uniones del segundo socket") { factory.sockets.count == 2 && factory.sockets[1].sent.count == 2 }
        XCTAssertTrue(factory.sockets[1].sent.allSatisfy { $0.contains("token-2") })
    }

    func testSiElCursorDelServidorFallaIgualQuedaEnVivoSinRecuperar() async throws {
        let factory = FakeSocketFactory(), recorder = SignalRecorder(), log = CatchUpLog()
        let failingHead: @Sendable () async throws -> String = { throw TestFailure() }
        let consumer = consume(makeService(factory, log: log, head: failingHead), into: recorder)
        defer { consumer.cancel() }

        await eventually("debe abrir el primer socket") { factory.sockets.count == 1 }
        let first = try XCTUnwrap(factory.sockets.first)
        joinAll(first)
        await eventually("debe quedar en vivo") { await recorder.signals.last == RealtimeSignal.state(.live) }
        let cursors = await log.cursors
        XCTAssertTrue(cursors.isEmpty)
    }
}

private struct TestFailure: Error {}

private actor TokenSource {
    private var count = 0
    func next() -> String {
        count += 1
        return "token-\(count)"
    }
}
