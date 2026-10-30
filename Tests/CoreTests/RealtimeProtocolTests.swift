import XCTest
@testable import ClimesaCore

final class RealtimeProtocolTests: XCTestCase {
    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testConstruyeLaURLDelSocketDesdeLaDireccionHttps() {
        XCTAssertEqual(
            RealtimeProtocol.websocketURL(supabaseURL: "https://ejemplo.supabase.co/", publishableKey: "clave"),
            "wss://ejemplo.supabase.co/realtime/v1/websocket?apikey=clave&vsn=1.0.0"
        )
        XCTAssertEqual(
            RealtimeProtocol.websocketURL(supabaseURL: "http://localhost:54321", publishableKey: "clave"),
            "ws://localhost:54321/realtime/v1/websocket?apikey=clave&vsn=1.0.0"
        )
    }

    func testLaRutaDeRecuperacionCodificaElCursor() {
        XCTAssertEqual(RealtimeProtocol.catchUpPath(after: "42"), "/eventos?after=42")
        XCTAssertEqual(RealtimeProtocol.catchUpPath(after: "a b"), "/eventos?after=a%20b")
    }

    func testLaUnionALosCanalesPrivadosLlevaTokenYBanderaPrivada() throws {
        let privado = try object(RealtimeProtocol.join(channel: "rol:ENF", ref: "1", accessToken: "token-ejemplo"))
        XCTAssertEqual(privado["topic"] as? String, "realtime:rol:ENF")
        XCTAssertEqual(privado["event"] as? String, "phx_join")
        XCTAssertEqual(privado["ref"] as? String, "1")
        XCTAssertEqual(privado["join_ref"] as? String, "1")
        let payload = try XCTUnwrap(privado["payload"] as? [String: Any])
        XCTAssertEqual(payload["access_token"] as? String, "token-ejemplo")
        let config = try XCTUnwrap(payload["config"] as? [String: Any])
        XCTAssertEqual(config["private"] as? Bool, true)

        let publico = try object(RealtimeProtocol.join(channel: "publico", ref: "2", accessToken: "token-ejemplo"))
        let publicConfig = try XCTUnwrap((publico["payload"] as? [String: Any])?["config"] as? [String: Any])
        XCTAssertEqual(publicConfig["private"] as? Bool, false)
    }

    func testElLatidoUsaElTopicDelProtocolo() throws {
        let latido = try object(RealtimeProtocol.heartbeat(ref: "7"))
        XCTAssertEqual(latido["topic"] as? String, "phoenix")
        XCTAssertEqual(latido["event"] as? String, "heartbeat")
        XCTAssertEqual(latido["ref"] as? String, "7")
        XCTAssertNil(latido["join_ref"])
    }

    func testInterpretaUnaDifusionDeCambioDeCama() {
        let texto = #"{"topic":"realtime:area:2","event":"broadcast","ref":null,"payload":{"event":"cama.estado_cambiado","type":"broadcast","payload":{"tipo":"cama.estado_cambiado","entidad":"cama","id":"b1","version":7}}}"#
        XCTAssertEqual(
            RealtimeProtocol.parse(texto),
            .broadcast(channel: "area:2", event: DomainEvent(type: "cama.estado_cambiado", entity: "cama", id: "b1", version: 7))
        )
    }

    func testUsaElNombreDelEventoSiLaCargaNoTrataTipo() {
        let texto = #"{"topic":"realtime:publico","event":"broadcast","payload":{"event":"aviso.publicado","payload":{"entidad":"aviso","id":5,"version":"3"}}}"#
        XCTAssertEqual(
            RealtimeProtocol.parse(texto),
            .broadcast(channel: "publico", event: DomainEvent(type: "aviso.publicado", entity: "aviso", id: "5", version: 3))
        )
    }

    func testReconoceLaRespuestaDeUnionYLosCierres() {
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:publico","event":"phx_reply","payload":{"status":"ok","response":{}},"ref":"1"}"#), .joinReply(channel: "publico", ok: true))
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:rol:ENF","event":"phx_reply","payload":{"status":"error"},"ref":"1"}"#), .joinReply(channel: "rol:ENF", ok: false))
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:rol:ENF","event":"phx_close","payload":{}}"#), .channelClosed(channel: "rol:ENF"))
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:rol:ENF","event":"phx_error","payload":{}}"#), .channelClosed(channel: "rol:ENF"))
    }

    func testIgnoraLatidosYTextoMalFormado() {
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"phoenix","event":"phx_reply","payload":{"status":"ok"}}"#), .ignored)
        XCTAssertEqual(RealtimeProtocol.parse("no es json"), .ignored)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:publico","event":"broadcast","payload":{"payload":{}}}"#), .ignored)
    }

    func testInterpretaLaRecuperacionDeEventos() throws {
        let datos = Data(#"{"cursor":"42","events":[{"seq":"41","type":"cama.estado_cambiado","entity":"cama","id":"b1","version":3}]}"#.utf8)
        let recuperado = try XCTUnwrap(RealtimeProtocol.parseCatchUp(data: datos))
        XCTAssertEqual(recuperado.cursor, "42")
        XCTAssertEqual(recuperado.events, [DomainEvent(type: "cama.estado_cambiado", entity: "cama", id: "b1", version: 3)])
    }

    func testLaRecuperacionAceptaCursorNumericoYSinEventos() throws {
        let numerico = try XCTUnwrap(RealtimeProtocol.parseCatchUp(data: Data(#"{"cursor":9,"events":[]}"#.utf8)))
        XCTAssertEqual(numerico.cursor, "9")
        XCTAssertTrue(numerico.events.isEmpty)
        let vacio = try XCTUnwrap(RealtimeProtocol.parseCatchUp(data: Data("{}".utf8)))
        XCTAssertEqual(vacio.cursor, "0")
        XCTAssertNil(RealtimeProtocol.parseCatchUp(data: Data("[]".utf8)))
    }
}

final class LiveStateTests: XCTestCase {
    private let turno = DomainEvent(type: "turno.publicado", entity: "turno", id: "t1", version: 1)
    private let cama = DomainEvent(type: "cama.estado_cambiado", entity: "cama", id: "b1", version: 1)

    func testUnEventoDeTurnoInvalidaTurnosYUnoDeCamaSoloLaVersionGeneral() {
        let afterShift = LiveReducer.apply(.event(turno), to: LiveSnapshot())
        XCTAssertEqual(afterShift.version, 1)
        XCTAssertEqual(afterShift.shiftsVersion, 1)
        let afterBed = LiveReducer.apply(.event(cama), to: afterShift)
        XCTAssertEqual(afterBed.version, 2)
        XCTAssertEqual(afterBed.shiftsVersion, 1)
    }

    func testResincronizarVuelveAPedirTodo() {
        let next = LiveReducer.apply(.resync, to: LiveSnapshot())
        XCTAssertEqual(next.version, 1)
        XCTAssertEqual(next.shiftsVersion, 1)
    }

    func testUnEventoDeUsuarioPideVerificarElPerfil() {
        let usuario = DomainEvent(type: "usuario.actualizado", entity: "usuario", id: "u1", version: 2)
        XCTAssertEqual(LiveReducer.apply(.event(usuario), to: LiveSnapshot()).profileVersion, 1)
        XCTAssertEqual(LiveReducer.apply(.event(cama), to: LiveSnapshot()).profileVersion, 0)
    }

    func testElEstadoDeConexionNoInvalidaDatos() {
        let next = LiveReducer.apply(.state(.live), to: LiveSnapshot())
        XCTAssertEqual(next.connection, .live)
        XCTAssertEqual(next.version, 0)
        XCTAssertEqual(LiveSnapshot().connection, .reconnecting)
    }
}
