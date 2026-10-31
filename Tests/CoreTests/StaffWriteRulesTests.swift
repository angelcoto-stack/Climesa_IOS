import XCTest
import Foundation
@testable import ClimesaCore

/// Reglas puras de alta, edición e inactivación de personal (datos ficticios).
final class StaffWriteRulesTests: XCTestCase {
    private func profile(_ codes: [String]) -> AccessProfile {
        let permissions = (["sesion.perfil"] + codes).map { Permission(code: $0, context: "propio") }
        return AccessProfile(id: "u1", email: "ejemplo@example.test", name: "Cuenta ficticia", roles: ["MED"],
                             platforms: ["ios"], permissions: permissions)
    }

    private func member(active: Bool? = true, version: Int? = 5) -> StaffMember {
        return StaffMember(id: "s1", givenNames: "Luis", surnames: "Ficticio", type: "medico",
                           specialty: "Cardiología", area: nil, active: active, version: version, registrations: nil)
    }

    private func validDraft(type: String = "medico") -> StaffDraft {
        return StaffDraft(givenNames: "Luis Alberto", surnames: "Ficticio Prueba", type: type,
                          specialty: "Medicina interna", dui: "01234567-8", phone: "7777 1234")
    }

    private let manage = "personal.gestionar"
    private let personalData = "personal.ver_datos_personales"
    private let reasonOK = "Corrección de especialidad ficticia"

    private func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func testFuncionesElegiblesVienenDeLasEtiquetas() {
        XCTAssertTrue(StaffLabels.functionCodes.contains("medico"))
        XCTAssertEqual(StaffLabels.functionCodes, StaffLabels.functionCodes.sorted())
    }

    func testFormularioValidoNoTieneErrores() {
        XCTAssertEqual(StaffWriteRules.draftErrors(validDraft()), [])
    }

    func testFuncionDesconocidaOVaciaSeRechaza() {
        XCTAssertFalse(StaffWriteRules.draftErrors(validDraft(type: "")).isEmpty)
        XCTAssertFalse(StaffWriteRules.draftErrors(validDraft(type: "cirujano")).isEmpty)
    }

    func testAltaSinPermisoGestionarSeRechaza() {
        let result = StaffWriteRules.prepareCreate(validDraft(), profile: profile([personalData]))
        XCTAssertNotNil(failureText(result))
    }

    func testAltaSinDatosPersonalesOmiteDUIYTelefono() throws {
        let request = try XCTUnwrap(successValue(StaffWriteRules.prepareCreate(validDraft(), profile: profile([manage]))))
        XCTAssertNil(request.dui)
        XCTAssertNil(request.phone)
        XCTAssertEqual(request.specialty, "Medicina interna")
        XCTAssertFalse(try encoded(request).contains("\"dui\""))
    }

    func testAltaConDatosPersonalesIncluyeDUIYTelefono() throws {
        let request = try XCTUnwrap(successValue(StaffWriteRules.prepareCreate(validDraft(),
                                                                               profile: profile([manage, personalData]))))
        XCTAssertEqual(request.dui, "01234567-8")
        XCTAssertEqual(request.phone, "7777 1234")
    }

    func testEdicionRequiereVersionYMotivo() throws {
        let editor = profile([manage])
        let missingVersion = StaffWriteRules.prepareUpdate(validDraft(), current: member(version: nil), reason: reasonOK, profile: editor)
        XCTAssertNotNil(failureText(missingVersion))
        XCTAssertNotNil(failureText(StaffWriteRules.prepareUpdate(validDraft(), current: member(), reason: "corto", profile: editor)))
        let request = try XCTUnwrap(successValue(StaffWriteRules.prepareUpdate(validDraft(), current: member(version: 8),
                                                                               reason: reasonOK, profile: editor)))
        XCTAssertEqual(request.version, 8)
        XCTAssertTrue(request.active)
    }

    func testEdicionSinPermisoDeDatosPersonalesNoEnviaDUI() throws {
        var draft = validDraft()
        draft.dui = "01234567-8"
        let request = try XCTUnwrap(successValue(StaffWriteRules.prepareUpdate(draft, current: member(), reason: reasonOK,
                                                                               profile: profile([manage]))))
        XCTAssertNil(request.dui)
    }

    func testInactivarConservaRegistroConMotivoYVersion() throws {
        XCTAssertEqual(failureText(StaffWriteRules.prepareActiveChange(member(active: false), active: false,
                                                                       reason: reasonOK, profile: profile([manage]))),
                       "Esta persona ya está inactiva.")
        let request = try XCTUnwrap(successValue(StaffWriteRules.prepareActiveChange(member(version: 6), active: false,
                                                                                     reason: reasonOK, profile: profile([manage]))))
        XCTAssertFalse(request.active)
        XCTAssertEqual(request.version, 6)
        XCTAssertEqual(request.givenNames, "Luis")
        XCTAssertNotNil(failureText(StaffWriteRules.prepareActiveChange(member(), active: false, reason: "corto",
                                                                        profile: profile([manage]))))
    }

    func testInactivarSinPermisoSeRechaza() {
        XCTAssertNotNil(failureText(StaffWriteRules.prepareActiveChange(member(), active: false, reason: reasonOK,
                                                                        profile: profile([personalData]))))
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
