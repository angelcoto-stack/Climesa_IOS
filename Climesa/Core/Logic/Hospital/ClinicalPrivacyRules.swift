/// Capa de presentación, nunca autorización del servidor.
public enum ClinicalPrivacyRules {
    public static func canReadRecord(profile: AccessProfile, patientID: String, treatingDoctorIDs: Set<String>) -> Bool {
        guard profile.hasPermission("expediente.ver") else { return false }
        let patient = patientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !patient.isEmpty else { return false }
        if profile.roles.contains("PAC") && profile.id == patient { return true }
        return profile.roles.contains("MED") && treatingDoctorIDs.contains(profile.id)
    }

    public static func canReadPublicOccupancy(profile: AccessProfile?) -> Bool { true }
}