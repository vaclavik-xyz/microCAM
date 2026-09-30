import XCTest
@testable import MicroCAMCore

final class LanguagePreferenceTests: XCTestCase {
    let available = ["cs", "en"]

    func testNoStoredValueMeansSystem() {
        XCTAssertNil(LanguagePreference.choice(appleLanguages: nil, available: available))
        XCTAssertNil(LanguagePreference.choice(appleLanguages: [], available: available))
    }

    func testStoredLanguageIsRecognisedByItsPrimaryCode() {
        XCTAssertEqual(LanguagePreference.choice(appleLanguages: ["cs"], available: available), "cs")
        XCTAssertEqual(LanguagePreference.choice(appleLanguages: ["en-GB", "cs"], available: available), "en")
        XCTAssertEqual(LanguagePreference.choice(appleLanguages: ["cs-CZ"], available: available), "cs")
    }

    func testUnknownStoredLanguageShowsAsSystem() {
        XCTAssertNil(LanguagePreference.choice(appleLanguages: ["de"], available: available))
    }

    func testValueToStore() {
        XCTAssertNil(LanguagePreference.appleLanguages(for: nil))
        XCTAssertEqual(LanguagePreference.appleLanguages(for: "cs"), ["cs"])
    }

    func testChoicesSkipBaseAndAreSorted() {
        XCTAssertEqual(LanguagePreference.choices(bundleLocalizations: ["en", "Base", "cs"]), ["cs", "en"])
        // The built app reports each language twice (lproj folders and
        // CFBundleLocalizations); the picker listed "Čeština" and "English" twice.
        XCTAssertEqual(LanguagePreference.choices(bundleLocalizations: ["en", "cs", "en", "cs"]), ["cs", "en"])
    }
}
