import Foundation

/// Qué acciones de las maquetas de médico y paciente se muestran según los permisos del catálogo (`permisos.csv`).
/// Nunca se decide por el nombre del rol.
public enum FlowVisibility {
    // Paciente
    public static func showsRequestAppointment(_ profile: AccessProfile) -> Bool { profile.hasPermission("citas.solicitar") }
    public static func showsMedicalHistory(_ profile: AccessProfile) -> Bool { profile.hasPermission("expediente.ver") }
    public static func showsAmbulanceRequest(_ profile: AccessProfile) -> Bool { profile.hasPermission("ambulancia.solicitar") }

    // Médico
    public static func showsStartConsultation(_ profile: AccessProfile) -> Bool { profile.hasPermission("consulta.iniciar") }
    public static func showsHospitalized(_ profile: AccessProfile) -> Bool { profile.hasPermission("admision.ver") }
}
