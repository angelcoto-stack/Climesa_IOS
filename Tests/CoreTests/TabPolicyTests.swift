import XCTest
import Foundation
@testable import ClimesaCore

/// Casos adicionales de TabPolicy y AccessProfile (datos ficticios).
final class TabPolicyTests: XCTestCase {
    private func perm(_ code: String) -> Permission { Permission(code: code, context: "propio") }

    private var allPermissions: [Permission] {
        return ["sesion.perfil", "pacientes.buscar", "turnos.ver", "fila.ver", "citas.ver"].map { perm($0) }
    }

    private func profile(_ roles: [String], platforms: [String] = ["ios"], permissions: [Permission]) -> AccessProfile {
        return AccessProfile(id: "u1", email: "ejemplo@example.test", name: "Cuenta ficticia", roles: roles, platforms: platforms, permissions: permissions)
    }

    private func decodeProfile(_ json: String) throws -> AccessProfile {
        return try JSONDecoder().decode(AccessProfile.self, from: Data(json.utf8))
    }

    // MARK: - TabPolicy.decide

    func testMedicoConTodosLosPermisosVeLasPestanasEnElOrdenDeLaEspecificacion() {
        let decision: AccessDecision = TabPolicy.decide(profile(["MED"], permissions: allPermissions))
        let expected: AccessDecision = .tabs(role: "MED", tabs: [.miDia, .pacientes, .resultados, .turnos, .perfil])
        XCTAssertEqual(decision, expected)
    }

    func testPacienteConTodosLosPermisosVeLasPestanasEnElOrdenDeLaEspecificacion() {
        let decision: AccessDecision = TabPolicy.decide(profile(["PAC"], permissions: allPermissions))
        let expected: AccessDecision = .tabs(role: "PAC", tabs: [.inicio, .fila, .citas, .examenes, .mas])
        XCTAssertEqual(decision, expected)
    }

    func testMedicoSinTurnosVerNoVeLaPestanaTurnos() {
        let permissions: [Permission] = [perm("sesion.perfil"), perm("pacientes.buscar")]
        let decision: AccessDecision = TabPolicy.decide(profile(["MED"], permissions: permissions))
        let expected: AccessDecision = .tabs(role: "MED", tabs: [.miDia, .pacientes, .resultados, .perfil])
        XCTAssertEqual(decision, expected)
    }

    func testMedicoSinBuscarPacientesNoVeLaPestanaPacientes() {
        let permissions: [Permission] = [perm("sesion.perfil"), perm("turnos.ver")]
        let decision: AccessDecision = TabPolicy.decide(profile(["MED"], permissions: permissions))
        let expected: AccessDecision = .tabs(role: "MED", tabs: [.miDia, .resultados, .turnos, .perfil])
        XCTAssertEqual(decision, expected)
    }

    func testPacienteSinFilaNiCitasSoloVeInicioExamenesYMas() {
        let decision: AccessDecision = TabPolicy.decide(profile(["PAC"], permissions: [perm("sesion.perfil")]))
        let expected: AccessDecision = .tabs(role: "PAC", tabs: [.inicio, .examenes, .mas])
        XCTAssertEqual(decision, expected)
    }

    func testPacienteSinFilaVerConservaCitas() {
        let permissions: [Permission] = [perm("sesion.perfil"), perm("citas.ver")]
        let decision: AccessDecision = TabPolicy.decide(profile(["PAC"], permissions: permissions))
        let expected: AccessDecision = .tabs(role: "PAC", tabs: [.inicio, .citas, .examenes, .mas])
        XCTAssertEqual(decision, expected)
    }

    func testCuentaConAmbosRolesEntraComoMedicoSiNoHayRolPreferido() {
        let decision: AccessDecision = TabPolicy.decide(profile(["PAC", "MED"], permissions: allPermissions))
        let expected: AccessDecision = .tabs(role: "MED", tabs: [.miDia, .pacientes, .resultados, .turnos, .perfil])
        XCTAssertEqual(decision, expected)
    }

    func testRolPreferidoMedicoEnCuentaConAmbosRoles() {
        let decision: AccessDecision = TabPolicy.decide(profile(["MED", "PAC"], permissions: allPermissions), preferredRole: "MED")
        let expected: AccessDecision = .tabs(role: "MED", tabs: [.miDia, .pacientes, .resultados, .turnos, .perfil])
        XCTAssertEqual(decision, expected)
    }

    func testRolPreferidoQueLaCuentaNoTieneSeIgnora() {
        let decision: AccessDecision = TabPolicy.decide(profile(["PAC"], permissions: allPermissions), preferredRole: "MED")
        let expected: AccessDecision = .tabs(role: "PAC", tabs: [.inicio, .fila, .citas, .examenes, .mas])
        XCTAssertEqual(decision, expected)
    }

    func testLosRolesSinSoporteEnIOSNoUsanLaAplicacion() {
        let unsupported: [String] = ["REC", "ADM", "AST", "ENF", "LAB", "PAR", "DPD", "JOP"]
        for role in unsupported {
            let decision: AccessDecision = TabPolicy.decide(profile([role], permissions: allPermissions))
            XCTAssertEqual(decision, AccessDecision.unsupportedRole, "el rol \(role) no debe entrar")
        }
    }

    func testUnRolNoSoportadoJuntoAMedicoSoloMuestraLasPestanasDelMedico() {
        let decision: AccessDecision = TabPolicy.decide(profile(["ENF", "MED"], permissions: allPermissions))
        let expected: AccessDecision = .tabs(role: "MED", tabs: [.miDia, .pacientes, .resultados, .turnos, .perfil])
        XCTAssertEqual(decision, expected)
    }

    func testSinRolesLaCuentaNoUsaLaAplicacion() {
        let decision: AccessDecision = TabPolicy.decide(profile([], permissions: allPermissions))
        XCTAssertEqual(decision, AccessDecision.unsupportedRole)
    }

    func testSinPermisoDePerfilLaCuentaNoUsaLaAplicacion() {
        let permissions: [Permission] = [perm("turnos.ver"), perm("pacientes.buscar")]
        let decision: AccessDecision = TabPolicy.decide(profile(["MED"], permissions: permissions))
        XCTAssertEqual(decision, AccessDecision.unsupportedRole)
    }

    func testSinPlataformaIOSLaCuentaNoUsaLaAplicacion() {
        let decision: AccessDecision = TabPolicy.decide(profile(["PAC"], platforms: ["android", "web"], permissions: allPermissions))
        XCTAssertEqual(decision, AccessDecision.unsupportedRole)
    }

    func testLasPestanasCandidatasDeCadaRolTienenCincoElementos() {
        XCTAssertEqual(TabPolicy.candidates(for: "MED"), [.miDia, .pacientes, .resultados, .turnos, .perfil])
        XCTAssertEqual(TabPolicy.candidates(for: "PAC"), [.inicio, .fila, .citas, .examenes, .mas])
    }

    func testCadaPestanaTieneSimboloYSoloAlgunasExigenPermiso() {
        for tab in AppTab.allCases {
            XCTAssertFalse(tab.symbol.isEmpty)
        }
        XCTAssertEqual(AppTab.pacientes.requiredPermission, "pacientes.buscar")
        XCTAssertEqual(AppTab.turnos.requiredPermission, "turnos.ver")
        XCTAssertEqual(AppTab.fila.requiredPermission, "fila.ver")
        XCTAssertEqual(AppTab.citas.requiredPermission, "citas.ver")
        XCTAssertNil(AppTab.perfil.requiredPermission)
        XCTAssertNil(AppTab.inicio.requiredPermission)
    }

    // MARK: - AccessProfile (JSON de /auth/me)

    func testDecodificaElPerfilConCanales() throws {
        let json = #"{"id":"u1","email":"ejemplo@example.test","name":"Cuenta ficticia","roles":["MED"],"platforms":["ios","web"],"permissions":[{"code":"sesion.perfil","context":"propio"},{"code":"turnos.ver","context":"propio"}],"channels":["publico","usuario:u1"]}"#
        let decoded: AccessProfile = try decodeProfile(json)
        XCTAssertEqual(decoded.id, "u1")
        XCTAssertEqual(decoded.roles, ["MED"])
        XCTAssertEqual(decoded.platforms, ["ios", "web"])
        XCTAssertEqual(decoded.permissions.count, 2)
        XCTAssertEqual(decoded.channels, ["publico", "usuario:u1"])
        XCTAssertTrue(decoded.hasPermission("turnos.ver"))
        XCTAssertFalse(decoded.hasPermission("fila.ver"))
    }

    func testDecodificaElPerfilSinCanalesYConCanalesNulos() throws {
        let sinCanales = #"{"id":"u1","email":"ejemplo@example.test","name":"Cuenta ficticia","roles":["PAC"],"platforms":["ios"],"permissions":[]}"#
        let nulos = #"{"id":"u1","email":"ejemplo@example.test","name":"Cuenta ficticia","roles":["PAC"],"platforms":["ios"],"permissions":[],"channels":null}"#
        XCTAssertTrue(try decodeProfile(sinCanales).channels.isEmpty)
        XCTAssertTrue(try decodeProfile(nulos).channels.isEmpty)
    }

    func testIgnoraLosCamposDesconocidosDelServidor() throws {
        let json = #"{"id":"u1","email":"ejemplo@example.test","name":"Cuenta ficticia","roles":["MED"],"platforms":["ios"],"permissions":[{"code":"sesion.perfil","context":"propio","extra":1}],"campo_nuevo":{"a":[1,2]},"channels":["publico"]}"#
        let decoded: AccessProfile = try decodeProfile(json)
        XCTAssertEqual(decoded.permissions.count, 1)
        XCTAssertEqual(decoded.channels, ["publico"])
        XCTAssertEqual(decoded.allowedIOSRoles, ["MED"])
    }

    func testUnPerfilConPermisosVaciosNoTienePermisosNiRolesDeIOS() throws {
        let json = #"{"id":"u1","email":"ejemplo@example.test","name":"Cuenta ficticia","roles":["MED","PAC"],"platforms":["ios"],"permissions":[]}"#
        let decoded: AccessProfile = try decodeProfile(json)
        XCTAssertTrue(decoded.permissions.isEmpty)
        XCTAssertFalse(decoded.hasPermission("sesion.perfil"))
        XCTAssertTrue(decoded.allowedIOSRoles.isEmpty)
        XCTAssertEqual(TabPolicy.decide(decoded), AccessDecision.unsupportedRole)
    }

    func testUnPerfilSinRolesEsInvalido() {
        let json = #"{"id":"u1","email":"ejemplo@example.test","name":"Cuenta ficticia","platforms":["ios"],"permissions":[]}"#
        XCTAssertThrowsError(try decodeProfile(json))
    }

    func testHasPermissionComparaSoloElCodigo() {
        let decoded: AccessProfile = profile(["MED"], permissions: [Permission(code: "turnos.ver", context: "todos")])
        XCTAssertTrue(decoded.hasPermission("turnos.ver"))
        XCTAssertFalse(decoded.hasPermission("turnos"))
        XCTAssertFalse(decoded.hasPermission("TURNOS.VER"))
    }
}
