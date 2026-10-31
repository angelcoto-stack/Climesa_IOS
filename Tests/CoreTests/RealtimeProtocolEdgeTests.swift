import XCTest
import Foundation
@testable import ClimesaCore

/// Casos límite del protocolo Phoenix: texto malformado, eventos desconocidos y respuestas de error.
final class RealtimeProtocolEdgeTests: XCTestCase {
    private func object(_ text: String) throws -> [String: Any] {
        let parsed: Any = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(parsed as? [String: Any])
    }

    // MARK: - parse

    func testTextoVacioOArregloNoSonMarcosValidos() {
        XCTAssertEqual(RealtimeProtocol.parse(""), RealtimeFrame.ignored)
        XCTAssertEqual(RealtimeProtocol.parse("[]"), RealtimeFrame.ignored)
        XCTAssertEqual(RealtimeProtocol.parse("{"), RealtimeFrame.ignored)
        XCTAssertEqual(RealtimeProtocol.parse("null"), RealtimeFrame.ignored)
    }

    func testUnMarcoSinTopicOConTopicAjenoSeIgnora() {
        XCTAssertEqual(RealtimeProtocol.parse(#"{"event":"broadcast","payload":{}}"#), RealtimeFrame.ignored)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"otro:publico","event":"phx_close","payload":{}}"#), RealtimeFrame.ignored)
    }

    func testUnEventoDesconocidoOSinNombreSeIgnora() {
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:publico","event":"presence_state","payload":{}}"#), RealtimeFrame.ignored)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:publico","payload":{}}"#), RealtimeFrame.ignored)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:publico","event":42,"payload":{}}"#), RealtimeFrame.ignored)
    }

    func testUnaRespuestaDeUnionConErrorOSinEstadoNoEsExito() {
        XCTAssertEqual(
            RealtimeProtocol.parse(#"{"topic":"realtime:rol:ENF","event":"phx_reply","payload":{"status":"error","response":{"reason":"denegado"}},"ref":"2"}"#),
            RealtimeFrame.joinReply(channel: "rol:ENF", ok: false)
        )
        XCTAssertEqual(
            RealtimeProtocol.parse(#"{"topic":"realtime:rol:ENF","event":"phx_reply","payload":{"status":"timeout"},"ref":"2"}"#),
            RealtimeFrame.joinReply(channel: "rol:ENF", ok: false)
        )
        XCTAssertEqual(
            RealtimeProtocol.parse(#"{"topic":"realtime:rol:ENF","event":"phx_reply","ref":"2"}"#),
            RealtimeFrame.joinReply(channel: "rol:ENF", ok: false)
        )
    }

    func testElCanalConservaLosDosPuntosDelNombre() {
        XCTAssertEqual(
            RealtimeProtocol.parse(#"{"topic":"realtime:usuario:u1","event":"phx_close","payload":{}}"#),
            RealtimeFrame.channelClosed(channel: "usuario:u1")
        )
    }

    func testUnaDifusionSinCargaInteriorOConTipoVacioSeIgnora() {
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:publico","event":"broadcast","payload":{}}"#), RealtimeFrame.ignored)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:publico","event":"broadcast","payload":{"payload":"texto"}}"#), RealtimeFrame.ignored)
        XCTAssertEqual(RealtimeProtocol.parse(#"{"topic":"realtime:publico","event":"broadcast","payload":{"event":"  ","payload":{"tipo":"  ","id":"1"}}}"#), RealtimeFrame.ignored)
    }

    func testElTipoDeclaradoSeRecortaYTienePrioridadSobreElNombreDelEvento() {
        let texto = #"{"topic":"realtime:publico","event":"broadcast","payload":{"event":"otro.nombre","payload":{"tipo":" turno.publicado ","entidad":"turno","id":"t1","version":4}}}"#
        let esperado: RealtimeFrame = .broadcast(channel: "publico", event: DomainEvent(type: "turno.publicado", entity: "turno", id: "t1", version: 4))
        XCTAssertEqual(RealtimeProtocol.parse(texto), esperado)
    }

    func testUnTipoEnBlancoUsaElNombreDelEventoYLosCamposFaltantesQuedanVacios() {
        let texto = #"{"topic":"realtime:publico","event":"broadcast","payload":{"event":"aviso.publicado","payload":{"tipo":"  ","entidad":null,"id":null,"version":"abc"}}}"#
        let esperado: RealtimeFrame = .broadcast(channel: "publico", event: DomainEvent(type: "aviso.publicado", entity: "", id: "", version: nil))
        XCTAssertEqual(RealtimeProtocol.parse(texto), esperado)
    }

    // MARK: - construcción de marcos

    func testLaUrlDelSocketRecortaEspaciosYBarrasFinales() {
        XCTAssertEqual(
            RealtimeProtocol.websocketURL(supabaseURL: "  https://ejemplo.supabase.co///  ", publishableKey: "clave"),
            "wss://ejemplo.supabase.co/realtime/v1/websocket?apikey=clave&vsn=1.0.0"
        )
        XCTAssertEqual(
            RealtimeProtocol.websocketURL(supabaseURL: "wss://ejemplo.test", publishableKey: "k"),
            "wss://ejemplo.test/realtime/v1/websocket?apikey=k&vsn=1.0.0"
        )
    }

    func testElMarcoDeUnionDelCanalPublicoNoEsPrivadoYLlevaConfiguracionBase() throws {
        let marco = try object(RealtimeProtocol.join(channel: "publico", ref: "3", accessToken: "token-ejemplo"))
        XCTAssertEqual(marco["topic"] as? String, "realtime:publico")
        XCTAssertEqual(marco["join_ref"] as? String, "3")
        let payload = try XCTUnwrap(marco["payload"] as? [String: Any])
        let config = try XCTUnwrap(payload["config"] as? [String: Any])
        let broadcast = try XCTUnwrap(config["broadcast"] as? [String: Any])
        XCTAssertEqual(broadcast["ack"] as? Bool, false)
        XCTAssertEqual(broadcast["self"] as? Bool, false)
        let cambios = try XCTUnwrap(config["postgres_changes"] as? [Any])
        XCTAssertTrue(cambios.isEmpty)
    }

    func testElLatidoNoLlevaCargaYUsaLaReferenciaIndicada() throws {
        let marco = try object(RealtimeProtocol.heartbeat(ref: "99"))
        let payload = try XCTUnwrap(marco["payload"] as? [String: Any])
        XCTAssertTrue(payload.isEmpty)
        XCTAssertEqual(marco["ref"] as? String, "99")
    }

    func testLasReferenciasDeLosMarcosSeConservanSinCambios() throws {
        let uno = try object(RealtimeProtocol.join(channel: "publico", ref: "1", accessToken: "t"))
        let dos = try object(RealtimeProtocol.join(channel: "publico", ref: "2", accessToken: "t"))
        XCTAssertEqual(uno["ref"] as? String, "1")
        XCTAssertEqual(dos["ref"] as? String, "2")
    }

    // MARK: - parseCatchUp

    func testLaRecuperacionConTextoQueNoEsJsonDevuelveNil() {
        XCTAssertNil(RealtimeProtocol.parseCatchUp(data: Data("no es json".utf8)))
        XCTAssertNil(RealtimeProtocol.parseCatchUp(data: Data()))
    }

    func testLaRecuperacionConCursorNuloOEventosInvalidosUsaValoresPorDefecto() throws {
        let nulo = try XCTUnwrap(RealtimeProtocol.parseCatchUp(data: Data(#"{"cursor":null,"events":[]}"#.utf8)))
        XCTAssertEqual(nulo.cursor, "0")
        let invalido = try XCTUnwrap(RealtimeProtocol.parseCatchUp(data: Data(#"{"cursor":"5","events":"texto"}"#.utf8)))
        XCTAssertEqual(invalido.cursor, "5")
        XCTAssertTrue(invalido.events.isEmpty)
    }

    func testLaRecuperacionDescartaFilasQueNoSonObjetosYConvierteIdsNumericos() throws {
        let datos = Data(#"{"cursor":12,"events":["basura",7,{"type":"cama.estado_cambiado","entity":"cama","id":33,"version":"5"},{"type":"turno.publicado","entity":"turno","id":"t9"}]}"#.utf8)
        let recuperado = try XCTUnwrap(RealtimeProtocol.parseCatchUp(data: datos))
        XCTAssertEqual(recuperado.cursor, "12")
        XCTAssertEqual(recuperado.events.count, 2)
        XCTAssertEqual(recuperado.events[0], DomainEvent(type: "cama.estado_cambiado", entity: "cama", id: "33", version: 5))
        XCTAssertEqual(recuperado.events[1], DomainEvent(type: "turno.publicado", entity: "turno", id: "t9", version: nil))
    }
}
