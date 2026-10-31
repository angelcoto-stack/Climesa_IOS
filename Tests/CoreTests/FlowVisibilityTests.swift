import XCTest
import Foundation
@testable import ClimesaCore

/// Visibilidad por permiso de las acciones de las maquetas (datos ficticios).
final class FlowVisibilityTests: XCTestCase {
    private func profile(_ codes: [String]) -> AccessProfile {
        let permissions = (["sesion.perfil"] + codes).map { Permission(code: $0, context: "propio") }
        return AccessProfile(id: "u1", email: "ejemplo@example.test", name: "Cuenta ficticia", roles: ["PAC"],
                             platforms: ["ios"], permissions: permissions)
    }

    func testPacienteSinPermisosNoVeAccionesDeMaqueta() {
        let empty = profile([])
        XCTAssertFalse(FlowVisibility.showsRequestAppointment(empty))
        XCTAssertFalse(FlowVisibility.showsMedicalHistory(empty))
        XCTAssertFalse(FlowVisibility.showsAmbulanceRequest(empty))
    }

    func testPacienteConPermisosVeSusAcciones() {
        let patient = profile(["citas.solicitar", "expediente.ver", "ambulancia.solicitar"])
        XCTAssertTrue(FlowVisibility.showsRequestAppointment(patient))
        XCTAssertTrue(FlowVisibility.showsMedicalHistory(patient))
        XCTAssertTrue(FlowVisibility.showsAmbulanceRequest(patient))
    }

    func testMedicoSoloVeConsultaYHospitalizadosConSuPermiso() {
        let doctorOnlyConsult = profile(["consulta.iniciar"])
        XCTAssertTrue(FlowVisibility.showsStartConsultation(doctorOnlyConsult))
        XCTAssertFalse(FlowVisibility.showsHospitalized(doctorOnlyConsult))
        XCTAssertTrue(FlowVisibility.showsHospitalized(profile(["admision.ver"])))
    }

    func testPermisoDeOtraAccionNoAbreLaMaqueta() {
        // Tener citas.ver no basta para pedir cita.
        XCTAssertFalse(FlowVisibility.showsRequestAppointment(profile(["citas.ver"])))
    }
}
