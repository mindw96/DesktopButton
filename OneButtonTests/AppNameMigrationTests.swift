import XCTest
@testable import OneButton

@MainActor
final class AppNameMigrationTests: XCTestCase {
    private let destination = URL(fileURLWithPath: "/Applications/Folder In Bar.app")
    private let now = Date(timeIntervalSince1970: 1000)

    func testLoginRestoreIsConsumedOnceAndPreservesExistingPreferences() throws {
        let suite = "AppNameMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1, 2, 3]), forKey: "desktopBookmark")
        defaults.set("icons", forKey: "desktopLayout")
        defaults.set(720, forKey: "popoverWidth")
        defaults.set(true, forKey: "showDockIcon")
        defaults.set(["destination": destination.path, "enabled": true, "createdAt": 999.0],
                     forKey: AppNameMigration.pendingKey)
        XCTAssertTrue(AppNameMigration.consumeLoginRestore(defaults: defaults, appURL: destination, now: now))
        XCTAssertFalse(AppNameMigration.consumeLoginRestore(defaults: defaults, appURL: destination, now: now))
        XCTAssertEqual(defaults.data(forKey: "desktopBookmark"), Data([1, 2, 3]))
        XCTAssertEqual(defaults.string(forKey: "desktopLayout"), "icons")
        XCTAssertEqual(defaults.integer(forKey: "popoverWidth"), 720)
        XCTAssertTrue(defaults.bool(forKey: "showDockIcon"))
    }

    func testDisabledExpiredMalformedAndOtherPathRecordsNeverEnableLogin() throws {
        let suite = "AppNameMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records: [[String: Any]] = [
            ["destination": destination.path, "enabled": false, "createdAt": 999.0],
            ["destination": destination.path, "enabled": true, "createdAt": 699.0],
            ["destination": destination.path, "enabled": true, "createdAt": 1001.0],
            ["destination": "/tmp/Folder In Bar.app", "enabled": true, "createdAt": 999.0],
            ["destination": destination.path, "enabled": true]
        ]
        for record in records {
            defaults.set(record, forKey: AppNameMigration.pendingKey)
            XCTAssertFalse(AppNameMigration.consumeLoginRestore(defaults: defaults, appURL: destination, now: now))
            XCTAssertNil(defaults.object(forKey: AppNameMigration.pendingKey))
        }
    }
}
