import AppKit
import XCTest
@testable import OneButton

@MainActor
final class DockIconControllerTests: XCTestCase {
    func testDefaultRemainsMenuBarOnly() {
        let suite = "OneButton.DockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = DockIconController(defaults: defaults, readPolicy: { .accessory }, applyPolicy: { _ in
            XCTFail("The current accessory policy must not be applied again")
            return false
        })

        XCTAssertFalse(controller.showsIcon)
        XCTAssertNil(defaults.object(forKey: "showDockIcon"))
        XCTAssertNil(controller.errorMessage)
    }

    func testSavedRegularPolicyIsNotReappliedWhenAlreadyActive() {
        let suite = "OneButton.DockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showDockIcon")
        let controller = DockIconController(defaults: defaults, readPolicy: { .regular }, applyPolicy: { _ in
            XCTFail("The current regular policy must not be applied again")
            return false
        })

        XCTAssertTrue(controller.showsIcon)
        XCTAssertTrue(defaults.bool(forKey: "showDockIcon"))
        XCTAssertNil(controller.errorMessage)
    }

    func testProhibitedPolicyStillChangesToAccessoryForMenuBarOnlyMode() {
        let suite = "OneButton.DockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var policies: [NSApplication.ActivationPolicy] = []
        let controller = DockIconController(defaults: defaults, readPolicy: { .prohibited }, applyPolicy: {
            policies.append($0)
            return true
        })

        XCTAssertEqual(policies, [.accessory])
        XCTAssertFalse(controller.showsIcon)
        XCTAssertNil(controller.errorMessage)
    }

    func testOptionAppliesImmediatelyAndRestoresFromSamePreferences() {
        let suite = "OneButton.DockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var policies: [NSApplication.ActivationPolicy] = []
        let controller = DockIconController(defaults: defaults, readPolicy: { .accessory }, applyPolicy: {
            policies.append($0)
            return true
        })

        controller.setShowsIcon(true)
        XCTAssertTrue(controller.showsIcon)
        XCTAssertTrue(defaults.bool(forKey: "showDockIcon"))
        controller.setShowsIcon(true)
        XCTAssertEqual(policies, [.regular])

        let restored = DockIconController(defaults: defaults, readPolicy: { .accessory }, applyPolicy: {
            policies.append($0)
            return true
        })
        XCTAssertTrue(restored.showsIcon)
        XCTAssertEqual(policies.last, .regular)
        restored.setShowsIcon(false)
        XCTAssertFalse(restored.showsIcon)
        XCTAssertFalse(defaults.bool(forKey: "showDockIcon"))
        XCTAssertEqual(policies.last, .accessory)
    }

    func testFailedChangePreservesPreferenceAndCanBeRetried() {
        let suite = "OneButton.DockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showDockIcon")
        var succeeds = true
        let controller = DockIconController(defaults: defaults, readPolicy: { .accessory }, applyPolicy: { _ in
            succeeds
        })

        succeeds = false
        controller.setShowsIcon(false)
        XCTAssertTrue(controller.showsIcon)
        XCTAssertTrue(defaults.bool(forKey: "showDockIcon"))
        XCTAssertNotNil(controller.errorMessage)

        succeeds = true
        controller.setShowsIcon(false)
        XCTAssertFalse(controller.showsIcon)
        XCTAssertFalse(defaults.bool(forKey: "showDockIcon"))
        XCTAssertNil(controller.errorMessage)
    }

    func testFailedRestorationReportsActualPolicyWithoutLosingSavedChoice() {
        let suite = "OneButton.DockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showDockIcon")
        let controller = DockIconController(defaults: defaults, readPolicy: { .accessory }, applyPolicy: { _ in false })

        XCTAssertFalse(controller.showsIcon)
        XCTAssertTrue(defaults.bool(forKey: "showDockIcon"))
        XCTAssertNotNil(controller.errorMessage)
        controller.dismissError()
        XCTAssertNil(controller.errorMessage)
    }
}
