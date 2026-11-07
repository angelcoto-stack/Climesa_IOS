import XCTest
import Foundation
@testable import ClimesaCore

final class PatientSearchConsistencyTests: XCTestCase {
    func testResultsOnlyMatchTheActiveSearch() {
        XCTAssertTrue(PatientRules.searchMatches("  Ana  ", submittedQuery: "Ana"))
        XCTAssertFalse(PatientRules.searchMatches("Ana María", submittedQuery: "Ana"))
        XCTAssertFalse(PatientRules.searchMatches("", submittedQuery: "Ana"))
        XCTAssertFalse(PatientRules.searchMatches("Ana", submittedQuery: ""))
    }

    func testSearchResponseDecodesRealAPIShape() throws {
        let json = """
        {
          "candidates": [{"id":"p-01","record":"EXP-01","givenNames":"Ana",
            "surnames":"Prueba","dui":null,"birth":null,"sex":"femenino",
            "phone":null,"active":true,"version":1}],
          "token":"search-token","expiresAt":"2026-11-09T12:00:00Z"
        }
        """
        let value = try JSONDecoder().decode(PatientSearchResult.self, from: Data(json.utf8))
        XCTAssertEqual(value.candidates.count, 1)
        XCTAssertEqual(value.candidates.first?.fullName, "Ana Prueba")
        XCTAssertEqual(value.token, "search-token")
    }
}
