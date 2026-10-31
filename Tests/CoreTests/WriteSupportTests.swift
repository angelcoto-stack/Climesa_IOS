import XCTest
import Foundation
@testable import ClimesaCore

/// Mapeo de errores de la API y claves de idempotencia de las escrituras (POST y PATCH).
final class WriteSupportTests: XCTestCase {
    private func body(_ json: String) -> Data { return Data(json.utf8) }

    // MARK: - Errores

    func testConflictoDeVersionPorCodigo() {
        let failure = ProblemMapper.failure(status: 409, body: body("{\"detail\":\"La versión no coincide.\",\"codigo\":\"version_conflicto\"}"))
        XCTAssertEqual(failure, .versionConflict("La versión no coincide."))
        XCTAssertTrue(failure.isVersionConflict)
    }

    func testConflictoDeVersionPorVersionActual() {
        let failure = ProblemMapper.failure(status: 409, body: body("{\"detail\":\"Cambió.\",\"versionActual\":5}"))
        XCTAssertEqual(failure, .versionConflict("Cambió."))
    }

    func testConflictoSinCuerpoUsaElTextoPorDefectoSoloConCodigo() {
        let failure = ProblemMapper.failure(status: 409, body: body("{\"codigo\":\"version_conflicto\"}"))
        XCTAssertEqual(failure, .versionConflict(ProblemMapper.defaultConflictMessage))
    }

    func testOtro409NoEsConflictoDeVersion() {
        let failure = ProblemMapper.failure(status: 409, body: body("{\"detail\":\"La unidad tiene un servicio activo.\",\"codigo\":\"servicio_activo\"}"))
        XCTAssertEqual(failure, .rejected("La unidad tiene un servicio activo."))
        XCTAssertFalse(failure.isVersionConflict)
    }

    func testCodigoDeConflictoConOtroEstadoNoEsConflicto() {
        let failure = ProblemMapper.failure(status: 400, body: body("{\"detail\":\"Dato inválido.\",\"codigo\":\"version_conflicto\"}"))
        XCTAssertEqual(failure, .rejected("Dato inválido."))
    }

    func testProblemJsonUsaDetail() {
        let failure = ProblemMapper.failure(status: 422, body: body("{\"type\":\"about:blank\",\"title\":\"Dato inválido\",\"status\":422,\"detail\":\"El motivo es obligatorio.\"}"))
        XCTAssertEqual(failure, .rejected("El motivo es obligatorio."))
    }

    func testFormatoAnteriorUsaErrorMessage() {
        let failure = ProblemMapper.failure(status: 400, body: body("{\"error\":{\"message\":\"Rango inválido.\"}}"))
        XCTAssertEqual(failure.text, "Rango inválido.")
    }

    func testCuerpoVacioOIlegibleUsaElRespaldo() {
        XCTAssertEqual(ProblemMapper.failure(status: 500, body: Data(), fallback: "Algo falló.").text, "Algo falló.")
        XCTAssertEqual(ProblemMapper.failure(status: 502, body: body("<html>Bad gateway</html>")).text, ProblemMapper.defaultMessage)
        XCTAssertEqual(ProblemMapper.failure(status: 400, body: body("{\"detail\":\"\"}"), fallback: "Respaldo").text, "Respaldo")
    }

    // MARK: - Idempotency-Key

    func testElMismoReintentoReutilizaLaClave() {
        var counter = 0
        var keys = IdempotencyKeys(generate: {
            counter += 1
            return "clave-\(counter)"
        })
        let signature = IdempotencyKeys.signature(method: "POST", path: "/ambulancia/mantenimiento", body: Data("{\"a\":1}".utf8))
        XCTAssertEqual(keys.key(for: signature), "clave-1")
        XCTAssertEqual(keys.key(for: signature), "clave-1")
        XCTAssertEqual(keys.pendingCount, 1)
    }

    func testSolicitudesDistintasUsanClavesDistintas() {
        var counter = 0
        var keys = IdempotencyKeys(generate: {
            counter += 1
            return "clave-\(counter)"
        })
        let first = IdempotencyKeys.signature(method: "POST", path: "/turnos/publicar", body: Data("{\"a\":1}".utf8))
        let second = IdempotencyKeys.signature(method: "POST", path: "/turnos/publicar", body: Data("{\"a\":2}".utf8))
        XCTAssertNotEqual(keys.key(for: first), keys.key(for: second))
    }

    func testMetodoYRutaFormanParteDeLaFirma() {
        let payload = Data("{}".utf8)
        let post = IdempotencyKeys.signature(method: "POST", path: "/turnos/1", body: payload)
        let patch = IdempotencyKeys.signature(method: "PATCH", path: "/turnos/1", body: payload)
        let other = IdempotencyKeys.signature(method: "PATCH", path: "/turnos/2", body: payload)
        XCTAssertNotEqual(post, patch)
        XCTAssertNotEqual(patch, other)
    }

    func testTerminadaLaSolicitudLaSiguienteUsaClaveNueva() {
        var counter = 0
        var keys = IdempotencyKeys(generate: {
            counter += 1
            return "clave-\(counter)"
        })
        let signature = IdempotencyKeys.signature(method: "PATCH", path: "/turnos/1", body: nil)
        XCTAssertEqual(keys.key(for: signature), "clave-1")
        keys.complete(signature)
        XCTAssertEqual(keys.pendingCount, 0)
        XCTAssertEqual(keys.key(for: signature), "clave-2")
    }

    func testLaClaveGeneradaPorDefectoCumpleElMinimoDeLaApi() {
        var keys = IdempotencyKeys()
        let key = keys.key(for: "POST /x ")
        XCTAssertGreaterThanOrEqual(key.count, 8)
        XCTAssertLessThanOrEqual(key.count, 128)
    }
}
