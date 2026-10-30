import XCTest
@testable import ClimesaCore

final class AccessTests: XCTestCase {
    private let basePermissions = [Permission(code: "sesion.perfil", context: "propio")]
    private let medicPermissions = [
        Permission(code: "sesion.perfil", context: "propio"),
        Permission(code: "pacientes.buscar", context: "todos"),
        Permission(code: "turnos.ver", context: "propio"),
        Permission(code: "fila.ver", context: "todos"),
        Permission(code: "citas.ver", context: "propio")
    ]

    func profile(_ roles: [String], _ platforms: [String], _ permissions: [Permission]? = nil, channels: [String] = []) -> AccessProfile {
        AccessProfile(id: "fixture", email: "ejemplo@example.test", name: "Cuenta ficticia", roles: roles, platforms: platforms, permissions: permissions ?? basePermissions, channels: channels)
    }

    func testOnlyTwoIOSRolesAreAllowed() { XCTAssertEqual(profile(["ADM", "MED", "PAC"], ["ios", "android"]).allowedIOSRoles, ["MED", "PAC"]) }

    func testOtherPlatformAndMissingPermissionDenyAccess() {
        XCTAssertTrue(profile(["MED"], ["web"]).allowedIOSRoles.isEmpty)
        XCTAssertTrue(profile(["PAC"], ["ios"], []).allowedIOSRoles.isEmpty)
    }

    func testMedicoVeSusCincoPestanas() {
        let decision = TabPolicy.decide(profile(["MED"], ["ios"], medicPermissions))
        XCTAssertEqual(decision, .tabs(role: "MED", tabs: [.miDia, .pacientes, .resultados, .turnos, .perfil]))
    }

    func testPacienteVeSusCincoPestanas() {
        let permissions = [Permission(code: "sesion.perfil", context: "propio"), Permission(code: "fila.ver", context: "propio"), Permission(code: "citas.ver", context: "propio")]
        let decision = TabPolicy.decide(profile(["PAC"], ["ios"], permissions))
        XCTAssertEqual(decision, .tabs(role: "PAC", tabs: [.inicio, .fila, .citas, .examenes, .mas]))
    }

    func testRecepcionistaNoUsaLaAplicacion() {
        XCTAssertEqual(TabPolicy.decide(profile(["REC"], ["ios", "web"], medicPermissions)), .unsupportedRole)
    }

    func testRolSinPlataformaIOSNoUsaLaAplicacion() {
        XCTAssertEqual(TabPolicy.decide(profile(["MED"], ["web"], medicPermissions)), .unsupportedRole)
    }

    func testUnaPestanaSeOcultaSiFaltaSuPermiso() {
        let decision = TabPolicy.decide(profile(["MED"], ["ios"]))
        XCTAssertEqual(decision, .tabs(role: "MED", tabs: [.miDia, .resultados, .perfil]))
    }

    func testCuentaConDosRolesRespetaElRolPreferidoSoloSiEstaPermitido() {
        let both = profile(["MED", "PAC"], ["ios"], medicPermissions)
        XCTAssertEqual(TabPolicy.decide(both, preferredRole: "PAC"), .tabs(role: "PAC", tabs: [.inicio, .fila, .citas, .examenes, .mas]))
        XCTAssertEqual(TabPolicy.decide(both, preferredRole: "REC"), .tabs(role: "MED", tabs: [.miDia, .pacientes, .resultados, .turnos, .perfil]))
    }

    func testSoloTurnosPerfilYMasEstanImplementadas() {
        let implemented = AppTab.allCases.filter { $0.isImplemented }
        XCTAssertEqual(Set(implemented), Set([AppTab.turnos, .perfil, .mas]))
    }

    func testCadaPestanaTieneClaveDeTitulo() {
        XCTAssertEqual(AppTab.miDia.titleKey, "tab.miDia")
        XCTAssertEqual(AppTab.examenes.titleKey, "tab.examenes")
        XCTAssertEqual(RolePolicy.labelKey("MED"), "role.MED")
        XCTAssertEqual(RolePolicy.labelKey("PAC"), "role.PAC")
    }

    func testElPerfilDecodificaLosCanalesYAceptaSuAusencia() throws {
        let withChannels = Data(#"{"id":"u1","email":"ejemplo@example.test","name":"Cuenta ficticia","roles":["MED"],"platforms":["ios"],"permissions":[{"code":"sesion.perfil","context":"propio"}],"channels":["publico","usuario:u1"]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AccessProfile.self, from: withChannels).channels, ["publico", "usuario:u1"])
        let without = Data(#"{"id":"u1","email":"ejemplo@example.test","name":"Cuenta ficticia","roles":["MED"],"platforms":["ios"],"permissions":[]}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(AccessProfile.self, from: without).channels.isEmpty)
    }

    func testRegistrationValidation() {
        XCTAssertTrue(RegistrationRules.errors(name: "Cuenta Ejemplo", email: "ejemplo@example.test", password: "Segura#2026", confirmation: "Segura#2026").isEmpty)
        XCTAssertEqual(RegistrationRules.errors(name: "A", email: "invalido", password: "123", confirmation: "456").count, 4)
    }
}
