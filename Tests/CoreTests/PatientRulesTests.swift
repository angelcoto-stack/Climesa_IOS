import XCTest
import Foundation
@testable import ClimesaCore

/// Reglas puras de pacientes: búsqueda previa, validaciones, permisos y motivos (datos ficticios).
final class PatientRulesTests: XCTestCase {
    private func profile(_ codes: [String]) -> AccessProfile {
        let permissions = (["sesion.perfil"] + codes).map { Permission(code: $0, context: "propio") }
        return AccessProfile(id: "u1", email: "ejemplo@example.test", name: "Cuenta ficticia", roles: ["MED"],
                             platforms: ["ios"], permissions: permissions)
    }

    private func record(active: Bool? = true, version: Int = 4) -> PatientRecord {
        return PatientRecord(id: "p1", record: "EXP-0001", givenNames: "Ana", surnames: "Ejemplo",
                             dui: nil, birth: "1990-05-12T00:00:00Z", sex: "femenino", phone: nil,
                             active: active, version: version)
    }

    private func validDraft() -> PatientDraft {
        return PatientDraft(givenNames: "Ana María", surnames: "Ejemplo Prueba", sex: .femenino)
    }

    private func search(expires: String = "2026-11-01T12:00:00Z") -> PatientSearchResult {
        return PatientSearchResult(candidates: [record()], token: "tok-ficticio", expiresAt: expires)
    }

    private var now: Date { OperationsDates.parse("2026-11-01T11:00:00Z") ?? Date() }

    private func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: - Búsqueda

    func testBusquedaNecesitaTresCaracteresYNoPasaDeCien() {
        XCTAssertNotNil(PatientRules.searchError("ab"))
        XCTAssertNil(PatientRules.searchError("  abc  "))
        XCTAssertNotNil(PatientRules.searchError(String(repeating: "a", count: 101)))
    }

    // MARK: - Validaciones del formulario

    func testFormularioValidoNoTieneErrores() {
        XCTAssertEqual(PatientRules.draftErrors(validDraft()), [])
    }

    func testSexoEsObligatorio() {
        var draft = validDraft()
        draft.sex = nil
        XCTAssertFalse(PatientRules.draftErrors(draft).isEmpty)
    }

    func testDUIConFormatoDeEspacio() {
        var draft = validDraft()
        draft.dui = "12345678"
        XCTAssertFalse(PatientRules.draftErrors(draft).isEmpty)
        draft.dui = "01234567-8"
        XCTAssertEqual(PatientRules.draftErrors(draft), [])
    }

    func testFechaDeNacimientoDebeExistir() {
        var draft = validDraft()
        draft.birth = "2026-02-30"
        XCTAssertFalse(PatientRules.draftErrors(draft).isEmpty)
        draft.birth = "1990-05-12"
        XCTAssertEqual(PatientRules.draftErrors(draft), [])
    }

    func testTelefonoTieneOchoDigitosSiSeEscribe() {
        var draft = validDraft()
        draft.phone = "7777-12"
        XCTAssertFalse(PatientRules.draftErrors(draft).isEmpty)
        draft.phone = "7777 1234"
        XCTAssertEqual(PatientRules.draftErrors(draft), [])
    }

    // MARK: - Alta: permiso y búsqueda previa

    func testAltaSinPermisoSeRechaza() {
        let result = PatientRules.prepareCreate(validDraft(), searchQuery: "Ana", search: search(),
                                                profile: profile(["pacientes.buscar"]), now: now)
        XCTAssertEqual(failureText(result), "No tienes permiso para registrar pacientes.")
    }

    func testAltaSinBusquedaPrevia() {
        let result = PatientRules.prepareCreate(validDraft(), searchQuery: "Ana", search: nil,
                                                profile: profile(["pacientes.registrar"]), now: now)
        XCTAssertNotNil(failureText(result))
    }

    func testAltaConBusquedaVencidaSeRechaza() {
        let expired = search(expires: "2026-11-01T10:00:00Z")
        let result = PatientRules.prepareCreate(validDraft(), searchQuery: "Ana", search: expired,
                                                profile: profile(["pacientes.registrar"]), now: now)
        XCTAssertNotNil(failureText(result))
    }

    func testAltaValidaOmiteOpcionalesVacios() throws {
        let result = PatientRules.prepareCreate(validDraft(), searchQuery: " Ana ", search: search(),
                                                profile: profile(["pacientes.registrar"]), now: now)
        let request = try XCTUnwrap(successValue(result))
        XCTAssertEqual(request.searchToken, "tok-ficticio")
        XCTAssertEqual(request.searchQuery, "Ana")
        XCTAssertEqual(request.sex, "femenino")
        let json = try encoded(request)
        XCTAssertFalse(json.contains("\"dui\""))
        XCTAssertFalse(json.contains("\"phone\""))
        XCTAssertTrue(json.contains("\"searchToken\":\"tok-ficticio\""))
    }

    // MARK: - Corrección y motivo

    func testCorreccionUsaLaVersionQueSeVio() throws {
        let result = PatientRules.prepareUpdate(validDraft(), current: record(version: 7), reason: "Corrección de nombre ficticio",
                                                profile: profile(["pacientes.editar_demograficos"]))
        XCTAssertEqual(try XCTUnwrap(successValue(result)).version, 7)
    }

    func testCorreccionMotivoDeDiezAQuinientos() {
        let profileWithEdit = profile(["pacientes.editar_demograficos"])
        XCTAssertNotNil(failureText(PatientRules.prepareUpdate(validDraft(), current: record(), reason: "corto",
                                                               profile: profileWithEdit)))
        let longReason = String(repeating: "m", count: 501)
        XCTAssertNotNil(failureText(PatientRules.prepareUpdate(validDraft(), current: record(), reason: longReason,
                                                               profile: profileWithEdit)))
    }

    func testCorreccionSinPermisoSeRechaza() {
        let result = PatientRules.prepareUpdate(validDraft(), current: record(), reason: "Motivo suficientemente largo",
                                                profile: profile(["pacientes.buscar"]))
        XCTAssertNotNil(failureText(result))
    }

    // MARK: - Inactivar y reactivar

    func testInactivarRequiereMotivoYVersion() throws {
        let editor = profile(["pacientes.editar_demograficos"])
        XCTAssertNotNil(failureText(PatientRules.prepareStateChange(record(active: true), active: false,
                                                                    reason: "corto", profile: editor)))
        let request = try XCTUnwrap(successValue(PatientRules.prepareStateChange(record(active: true, version: 9), active: false,
                                                                                 reason: "Duplicado confirmado en la búsqueda",
                                                                                 profile: editor)))
        XCTAssertEqual(request.active, false)
        XCTAssertEqual(request.version, 9)
    }

    func testNoInactivarUnPacienteYaInactivo() {
        let result = PatientRules.prepareStateChange(record(active: false), active: false,
                                                     reason: "Motivo suficientemente largo",
                                                     profile: profile(["pacientes.editar_demograficos"]))
        XCTAssertEqual(failureText(result), "El paciente ya está inactivo.")
    }

    // MARK: - Permisos de la pantalla

    func testPermisosDelCatalogoParaCadaAccion() {
        XCTAssertTrue(PatientRules.canSearch(profile(["pacientes.buscar"])))
        XCTAssertFalse(PatientRules.canRegister(profile(["pacientes.buscar"])))
        XCTAssertTrue(PatientRules.canRegister(profile(["pacientes.registrar"])))
        XCTAssertTrue(PatientRules.canEdit(profile(["pacientes.editar_demograficos"])))
        XCTAssertFalse(PatientRules.canEdit(profile(["pacientes.ver_ficha"])))
        XCTAssertTrue(PatientRules.canViewFile(profile(["pacientes.ver_ficha"])))
    }

    // MARK: - Decodificación de la ficha

    func testFichaDecodificaHistorialDelMismoObjeto() throws {
        let json = """
        {"id":"p1","record":"EXP-0001","givenNames":"Ana","surnames":"Ejemplo","sex":"femenino",
         "active":true,"version":2,
         "history":[{"version":2,"reason":"Corrección de teléfono ficticio","at":"2026-10-30T10:00:00Z",
                     "changes":{"telefono":{"before":null,"after":"7777-1234"}}}]}
        """
        let file = try JSONDecoder().decode(PatientFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.patient.fullName, "Ana Ejemplo")
        XCTAssertEqual(file.history.count, 1)
        XCTAssertEqual(file.history.first?.changes?["telefono"]?.after, "7777-1234")
    }

    // MARK: - Ayudas

    private func failureText<T>(_ result: Result<T, ValidationError>) -> String? {
        if case .failure(let error) = result { return error.message }
        return nil
    }

    private func successValue<T>(_ result: Result<T, ValidationError>) -> T? {
        if case .success(let value) = result { return value }
        return nil
    }
}
