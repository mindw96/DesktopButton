import Foundation
import XCTest
@testable import OneButton

@MainActor
final class LocalizationTests: XCTestCase {
    private func languageBundle(_ language: String) throws -> Bundle {
        let app = Bundle(for: DesktopStore.self)
        let url = try XCTUnwrap(app.url(forResource: language, withExtension: "lproj"))
        return try XCTUnwrap(Bundle(url: url))
    }

    private func entries(in bundle: Bundle, extension ext: String) throws -> [String: Any] {
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: ext))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            as? [String: Any])
    }

    func testBothLanguagesPackageTheSameNonemptyStringsAndPluralKeys() throws {
        let english = try languageBundle("en")
        let korean = try languageBundle("ko")
        let enStrings = try entries(in: english, extension: "strings")
        let koStrings = try entries(in: korean, extension: "strings")
        let enPlurals = try entries(in: english, extension: "stringsdict")
        let koPlurals = try entries(in: korean, extension: "stringsdict")
        XCTAssertFalse(enStrings.isEmpty)
        XCTAssertEqual(Set(enStrings.keys).union(enPlurals.keys), Set(koStrings.keys).union(koPlurals.keys))
        for strings in [enStrings, koStrings] {
            for (key, value) in strings {
                XCTAssertFalse((value as? String ?? "").isEmpty, key)
            }
        }
        XCTAssertNotNil(enPlurals["%lld items"])
        XCTAssertNotNil(koPlurals["%lld items"])
    }

    func testMenusAndFileErrorsResolveInEachLanguage() throws {
        let name = "문서 10 & notes.txt"
        let detail = "Example error"
        for language in ["en", "ko"] {
            let bundle = try languageBundle(language)
            XCTAssertEqual(bundle.localizedString(forKey: "Connect Folder", value: nil, table: nil),
                           language == "en" ? "Connect Folder" : "폴더 연결")
            XCTAssertEqual(bundle.localizedString(forKey: "Icon Size", value: nil, table: nil),
                           language == "en" ? "Icon Size" : "아이콘 크기")
            XCTAssertEqual(bundle.localizedString(forKey: "Date Modified", value: nil, table: nil),
                           language == "en" ? "Date Modified" : "수정일")
            let message = String(localized: "Could not open “\(name)”.\n\(detail)", bundle: bundle,
                                 locale: Locale(identifier: language))
            XCTAssertEqual(message, language == "en"
                           ? "Could not open “\(name)”.\n\(detail)"
                           : "‘\(name)’ 파일을 열지 못했습니다.\n\(detail)")
        }
    }

    func testItemCountUsesEnglishPluralRulesAndKoreanSuffix() throws {
        for language in ["en", "ko"] {
            let bundle = try languageBundle(language)
            for count in [0, 1, 2] {
                let countText = String(localized: "\(count) items", bundle: bundle,
                                       locale: Locale(identifier: language))
                XCTAssertEqual(countText, language == "ko" ? "\(count)개 항목"
                               : "\(count) \(count == 1 ? "item" : "items")")
            }
        }
    }

    func testDesktopPermissionExplanationIsAvailableInBothLanguages() throws {
        let en = try languageBundle("en").localizedString(
            forKey: "NSDesktopFolderUsageDescription", value: nil, table: "InfoPlist")
        let ko = try languageBundle("ko").localizedString(
            forKey: "NSDesktopFolderUsageDescription", value: nil, table: "InfoPlist")
        XCTAssertNotEqual(en, "NSDesktopFolderUsageDescription")
        XCTAssertNotEqual(ko, "NSDesktopFolderUsageDescription")
        XCTAssertNotEqual(en, ko)
        XCTAssertFalse(en.isEmpty)
        XCTAssertFalse(ko.isEmpty)
    }
}
