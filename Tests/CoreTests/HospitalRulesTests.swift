import XCTest
@testable import ClimesaCore

final class HospitalRulesTests: XCTestCase {
    func testExactRoomsAndBeds() {
        XCTAssertEqual(HospitalCatalog.vipRooms, ["VIP-301", "VIP-302", "VIP-303", "VIP-304", "VIP-305"])
        XCTAssertEqual(HospitalCatalog.sharedRooms.count, 6)
        XCTAssertEqual(HospitalCatalog.beds.count, 17)
        XCTAssertEqual(Set(HospitalCatalog.beds).count, 17)
        XCTAssertEqual(HospitalCatalog.room(for: "HAB-206-2"), "HAB-206")
    }

    func testNoDoubleBookingAndNoOvercapacity() {
        var assignments = [BedAssignment]()
        for (index, bed) in HospitalCatalog.beds.enumerated() {
            switch BedAllocationRules.assign(patientID: "p\(index)", bedID: bed, current: assignments) {
            case .success(let next): assignments = next
            case .failure(let error): XCTFail("Error inesperado: \(error)")
            }
        }
        XCTAssertTrue(BedAllocationRules.availableBeds(in: assignments).isEmpty)
        XCTAssertEqual(BedAllocationRules.assign(patientID: "extra", bedID: HospitalCatalog.beds[0], current: assignments), .failure(.bedOccupied))
        XCTAssertEqual(BedAllocationRules.assign(patientID: "p0", bedID: HospitalCatalog.beds[1], current: assignments), .failure(.patientAlreadyAssigned))
        XCTAssertEqual(BedAllocationRules.assign(patientID: "extra", bedID: "HAB-207-1", current: assignments), .failure(.unknownBed))
    }

    func testRejectsCorruptSnapshots() {
        let corrupt = [BedAssignment(patientID: "a", bedID: "VIP-301-1"), BedAssignment(patientID: "b", bedID: "VIP-301-1")]
        XCTAssertFalse(BedAllocationRules.validateSnapshot(corrupt))
        XCTAssertEqual(BedAllocationRules.assign(patientID: "c", bedID: "VIP-302-1", current: corrupt), .failure(.corruptSnapshot))
    }

    func testLabTransitions() {
        XCTAssertTrue(LabProgress.pending.canTransition(to: .processing))
        XCTAssertTrue(LabProgress.processing.canTransition(to: .complete))
        XCTAssertFalse(LabProgress.pending.canTransition(to: .complete))
        XCTAssertFalse(LabProgress.complete.canTransition(to: .pending))
    }

    func testMedicalRecordIsNotPublic() {
        let permissions = [Permission(code: "expediente.ver", context: "own")]
        let patient = AccessProfile(id: "patient-1", email: "p@test.com", name: "Paciente", roles: ["PAC"], platforms: ["ios"], permissions: permissions)
        let doctor = AccessProfile(id: "doctor-1", email: "m@test.com", name: "Médico", roles: ["MED"], platforms: ["ios"], permissions: permissions)
        XCTAssertTrue(ClinicalPrivacyRules.canReadRecord(profile: patient, patientID: "patient-1", treatingDoctorIDs: []))
        XCTAssertFalse(ClinicalPrivacyRules.canReadRecord(profile: patient, patientID: "patient-2", treatingDoctorIDs: []))
        XCTAssertFalse(ClinicalPrivacyRules.canReadRecord(profile: doctor, patientID: "patient-1", treatingDoctorIDs: []))
        XCTAssertTrue(ClinicalPrivacyRules.canReadRecord(profile: doctor, patientID: "patient-1", treatingDoctorIDs: ["doctor-1"]))
    }
}
