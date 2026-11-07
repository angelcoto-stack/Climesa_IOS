import Foundation
import XCTest
@testable import ClimesaCore

/// Pruebas del contrato local de asignación. No sustituyen pruebas de
/// concurrencia, persistencia ni autorización en el backend.
final class HospitalIntegrationTests: XCTestCase {
    func testInventoryHasCorrectCapacityPerFloor() {
        XCTAssertEqual(HospitalCatalog.vipRooms.count, 5)
        XCTAssertEqual(HospitalCatalog.sharedRooms.count, 6)
        XCTAssertEqual(HospitalCatalog.capacity, 17)
        XCTAssertEqual(HospitalCatalog.beds.count, HospitalCatalog.capacity)

        let vipBeds = HospitalCatalog.beds.filter { $0.hasPrefix("VIP-") }
        let sharedBeds = HospitalCatalog.beds.filter { $0.hasPrefix("HAB-") }
        XCTAssertEqual(vipBeds.count, 5)
        XCTAssertEqual(sharedBeds.count, 12)

        for room in HospitalCatalog.vipRooms {
            XCTAssertEqual(HospitalCatalog.beds.filter { $0.hasPrefix("\(room)-") }.count, 1)
        }
        for room in HospitalCatalog.sharedRooms {
            XCTAssertEqual(HospitalCatalog.beds.filter { $0.hasPrefix("\(room)-") }.count, 2)
        }
    }

    func testSequentialAssignmentsKeepOnePatientPerBed() throws {
        let first = try XCTUnwrap(BedAllocationRules.assign(
            patientID: "paciente-1", bedID: "VIP-301-1", current: []
        ).successValue)
        let second = try XCTUnwrap(BedAllocationRules.assign(
            patientID: "paciente-2", bedID: "HAB-201-1", current: first
        ).successValue)

        XCTAssertTrue(BedAllocationRules.validateSnapshot(second))
        XCTAssertEqual(second.count, 2)
        XCTAssertFalse(BedAllocationRules.availableBeds(in: second).contains("VIP-301-1"))
        XCTAssertFalse(BedAllocationRules.availableBeds(in: second).contains("HAB-201-1"))
        XCTAssertTrue(BedAllocationRules.availableBeds(in: second).contains("HAB-201-2"))
    }

    func testRejectsDuplicatePatientAndOccupiedBed() throws {
        let current = [BedAssignment(patientID: "paciente-1", bedID: "VIP-301-1")]

        XCTAssertEqual(
            BedAllocationRules.assign(patientID: "paciente-2", bedID: "VIP-301-1", current: current),
            .failure(.bedOccupied)
        )
        XCTAssertEqual(
            BedAllocationRules.assign(patientID: "paciente-1", bedID: "VIP-302-1", current: current),
            .failure(.patientAlreadyAssigned)
        )
        XCTAssertEqual(
            BedAllocationRules.assign(patientID: "   ", bedID: "VIP-302-1", current: current),
            .failure(.invalidPatient)
        )
    }

    func testRejectsInconsistentServerSnapshots() {
        let duplicateBed = [
            BedAssignment(patientID: "paciente-1", bedID: "VIP-301-1"),
            BedAssignment(patientID: "paciente-2", bedID: "VIP-301-1")
        ]
        let duplicatePatient = [
            BedAssignment(patientID: "paciente-1", bedID: "VIP-301-1"),
            BedAssignment(patientID: "paciente-1", bedID: "VIP-302-1")
        ]
        let unknownBed = [BedAssignment(patientID: "paciente-1", bedID: "HAB-999-1")]

        for invalid in [duplicateBed, duplicatePatient, unknownBed] {
            XCTAssertFalse(BedAllocationRules.validateSnapshot(invalid))
            XCTAssertTrue(BedAllocationRules.availableBeds(in: invalid).isEmpty)
            XCTAssertEqual(
                BedAllocationRules.assign(patientID: "nuevo", bedID: "HAB-201-2", current: invalid),
                .failure(.corruptSnapshot)
            )
        }
    }

    func testAssignmentsSurviveJSONRoundTrip() throws {
        let source = [
            BedAssignment(patientID: "paciente-1", bedID: "VIP-301-1"),
            BedAssignment(patientID: "paciente-2", bedID: "HAB-206-2")
        ]
        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode([BedAssignment].self, from: encoded)

        XCTAssertEqual(decoded, source)
        XCTAssertTrue(BedAllocationRules.validateSnapshot(decoded))
    }

    func testOccupiedBedRemainsUnavailableOnRepeatRead() {
        let snapshot = [BedAssignment(patientID: "paciente-1", bedID: "HAB-202-1")]
        let firstRead = BedAllocationRules.availableBeds(in: snapshot)
        let secondRead = BedAllocationRules.availableBeds(in: snapshot)

        XCTAssertEqual(firstRead, secondRead)
        XCTAssertEqual(firstRead.count, 16)
        XCTAssertFalse(firstRead.contains("HAB-202-1"))
    }
}

private extension Result where Success == [BedAssignment], Failure == AllocationError {
    var successValue: [BedAssignment]? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}
