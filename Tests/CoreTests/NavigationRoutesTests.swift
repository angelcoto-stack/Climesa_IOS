import XCTest
import Foundation
@testable import ClimesaCore

/// Cada pantalla iOS de pantallas.csv (MED y PAC) tiene una ruta de navegación alcanzable.
final class NavigationRoutesTests: XCTestCase {
    private func profile(role: String, codes: Set<String> = []) -> AccessProfile {
        let permissions = (["sesion.perfil"] + codes.sorted()).map { Permission(code: $0, context: "propio") }
        return AccessProfile(id: "u1", email: "ejemplo@example.test", name: "Cuenta ficticia", roles: [role],
                             platforms: ["ios"], permissions: permissions)
    }

    /// Todos los permisos que exigen las aristas y las pestañas: un perfil "completo" para cada rol.
    private var allCodes: Set<String> {
        var codes = Set(NavigationRoutes.edges.compactMap { $0.permission })
        for tab in AppTab.allCases {
            if let code = tab.requiredPermission { codes.insert(code) }
        }
        return codes
    }

    private var medico: AccessProfile { profile(role: "MED", codes: allCodes) }
    private var paciente: AccessProfile { profile(role: "PAC", codes: allCodes) }

    func testListaDeIOSCoincideConPantallasCsv() {
        XCTAssertEqual(NavigationRoutes.iosScreens, [
            "I01", "I02", "I03", "I04", "I05", "I06", "I07", "I08", "I09", "I10", "I11", "I12", "I13",
            "I20", "I21", "I22", "I23", "I24", "I25", "I26"
        ])
    }

    func testCadaPantallaIOSEsAlcanzableDesdeMedicoOPaciente() {
        let reachable = NavigationRoutes.reachable(for: medico).union(NavigationRoutes.reachable(for: paciente))
        for screen in NavigationRoutes.iosScreens {
            XCTAssertTrue(reachable.contains(screen), "\(screen) no tiene ruta de navegación")
        }
    }

    func testMedicoAlcanzaSusPantallasConPermisos() {
        let reachable = NavigationRoutes.reachable(for: medico)
        for screen in ["I20", "I21", "I22", "I23", "I24", "I25", "I26"] {
            XCTAssertTrue(reachable.contains(screen), "\(screen) debería verse con permisos de Médico")
        }
    }

    func testMedicoNoAlcanzaPantallasDePaciente() {
        let reachable = NavigationRoutes.reachable(for: medico)
        for screen in ["I03", "I04", "I05", "I06", "I07", "I08", "I09", "I11", "I13"] {
            XCTAssertFalse(reachable.contains(screen), "\(screen) no debería verse desde Médico")
        }
    }

    func testPacienteNoAlcanzaPantallasDeMedico() {
        let reachable = NavigationRoutes.reachable(for: paciente)
        for screen in ["I20", "I21", "I22", "I23", "I24", "I25", "I26"] {
            XCTAssertFalse(reachable.contains(screen), "\(screen) no debería verse desde Paciente")
        }
    }

    func testSinPermisoMedicoNoAlcanzaPantallasProtegidas() {
        let reachable = NavigationRoutes.reachable(for: profile(role: "MED"))
        XCTAssertTrue(reachable.contains("I20"))
        XCTAssertTrue(reachable.contains("I10"))
        for screen in ["I21", "I22", "I23", "I24", "I25", "I26"] {
            XCTAssertFalse(reachable.contains(screen), "\(screen) no debería verse sin permiso")
        }
    }

    func testSinPermisoPacienteNoAlcanzaSeccionesProtegidas() {
        let reachable = NavigationRoutes.reachable(for: profile(role: "PAC"))
        XCTAssertTrue(reachable.contains("I04"))
        XCTAssertTrue(reachable.contains("I13"))
        for screen in ["I03", "I05", "I06", "I07", "I08", "I09", "I11"] {
            XCTAssertFalse(reachable.contains(screen), "\(screen) no debería verse sin permiso")
        }
    }

    func testTodoOrigenYDestinoDeLaTablaEsUnNodoConocido() {
        var known = Set(NavigationRoutes.iosScreens)
        known.insert(NavigationRoutes.root)
        known.insert(NavigationRoutes.patientCareSection)
        for tab in AppTab.allCases { known.insert(NavigationRoutes.tabNode(tab)) }
        for edge in NavigationRoutes.edges {
            XCTAssertTrue(known.contains(edge.from), "origen desconocido: \(edge.from)")
            XCTAssertTrue(known.contains(edge.to), "destino desconocido: \(edge.to)")
        }
    }
}