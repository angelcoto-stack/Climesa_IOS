import Foundation

/// Identificadores y capacidades oficiales del hospital. La verificación definitiva
/// contra asignaciones concurrentes debe ejecutarse transaccionalmente en el backend.
public enum HospitalCatalog {
    public static let vipRooms = (301...305).map { "VIP-\($0)" }
    public static let sharedRooms = (201...206).map { "HAB-\($0)" }
    public static let beds = vipRooms.map { "\($0)-1" } + sharedRooms.flatMap { ["\($0)-1", "\($0)-2"] }
    public static let capacity = 17
    public static func room(for bed: String) -> String? {
        guard beds.contains(bed), let lastDash = bed.lastIndex(of: "-") else { return nil }
        return String(bed[..<lastDash])
    }
}

public struct BedAssignment: Codable, Equatable, Sendable {
    public let patientID: String
    public let bedID: String
    public init(patientID: String, bedID: String) { self.patientID = patientID; self.bedID = bedID }
}

public enum AllocationError: Error, Equatable, Sendable {
    case unknownBed, bedOccupied, patientAlreadyAssigned, invalidPatient, corruptSnapshot
}

/// Dominio puro para comprobación anticipada de asignación. No sustituye al bloqueo
/// y la restricción UNIQUE del servidor: dos clientes pueden leer el mismo estado.
public enum BedAllocationRules {
    public static func validateSnapshot(_ assignments: [BedAssignment]) -> Bool {
        let bedIDs = assignments.map(\.bedID)
        let patientIDs = assignments.map(\.patientID)
        return Set(bedIDs).count == bedIDs.count && Set(patientIDs).count == patientIDs.count
            && bedIDs.allSatisfy { HospitalCatalog.beds.contains($0) }
            && patientIDs.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public static func assign(patientID: String, bedID: String, current: [BedAssignment]) -> Result<[BedAssignment], AllocationError> {
        guard validateSnapshot(current) else { return .failure(.corruptSnapshot) }
        let patient = patientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !patient.isEmpty else { return .failure(.invalidPatient) }
        guard HospitalCatalog.beds.contains(bedID) else { return .failure(.unknownBed) }
        guard !current.contains(where: { $0.patientID == patient }) else { return .failure(.patientAlreadyAssigned) }
        guard !current.contains(where: { $0.bedID == bedID }) else { return .failure(.bedOccupied) }
        return .success(current + [BedAssignment(patientID: patient, bedID: bedID)])
    }

    public static func availableBeds(in assignments: [BedAssignment]) -> [String] {
        guard validateSnapshot(assignments) else { return [] }
        let used = Set(assignments.map(\.bedID))
        return HospitalCatalog.beds.filter { !used.contains($0) }
    }
}

public enum LabProgress: String, Codable, CaseIterable, Sendable {
    case pending = "Pendiente"
    case processing = "En Proceso"
    case complete = "Completado"

    public func canTransition(to next: LabProgress) -> Bool {
        switch (self, next) {
        case (.pending, .processing), (.processing, .complete): return true
        default: return false
        }
    }
}

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
