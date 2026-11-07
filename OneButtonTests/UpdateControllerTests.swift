import Sparkle
import XCTest
@testable import OneButton

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testDisabledUpdaterCannotStartAUserCheckOrChangePreferences() {
        let controller = UpdateController(isEnabled: false)
        var presentedUpdate = false
        controller.onWillPresentUpdate = { presentedUpdate = true }

        controller.checkForUpdates()
        controller.setAutomaticallyChecksForUpdates(true)
        controller.setAutomaticallyDownloadsUpdates(true)

        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
        XCTAssertFalse(controller.automaticallyDownloadsUpdates)
        XCTAssertFalse(presentedUpdate)
        XCTAssertNil(controller.availableUpdateVersion)
    }

    func testScheduledReminderDoesNotPresentUIAndClearsAfterAttentionOrSessionEnd() throws {
        let controller = UpdateController(isEnabled: false)
        // Sparkle's dictionary initializer is used only to construct this test fixture.
        let update = try XCTUnwrap(SUAppcastItem(dictionary: [
            "sparkle:version": "3",
            "sparkle:shortVersionString": "0.3.0",
            "link": "https://github.com/mindw96/DesktopButton"
        ]))
        let state = try XCTUnwrap(SPUUserUpdateState(coder: ScheduledUpdateStateDecoder()))
        var presentedUpdate = false
        controller.onWillPresentUpdate = { presentedUpdate = true }

        XCTAssertTrue(controller.supportsGentleScheduledUpdateReminders)
        XCTAssertFalse(controller.standardUserDriverShouldHandleShowingScheduledUpdate(
            update, andInImmediateFocus: false
        ))
        XCTAssertTrue(controller.standardUserDriverShouldHandleShowingScheduledUpdate(
            update, andInImmediateFocus: true
        ))

        controller.standardUserDriverWillHandleShowingUpdate(false, forUpdate: update, state: state)
        XCTAssertEqual(controller.availableUpdateVersion, "0.3.0")
        XCTAssertFalse(presentedUpdate)

        controller.standardUserDriverDidReceiveUserAttention(forUpdate: update)
        XCTAssertNil(controller.availableUpdateVersion)
        controller.standardUserDriverWillHandleShowingUpdate(false, forUpdate: update, state: state)
        controller.standardUserDriverWillFinishUpdateSession()
        XCTAssertNil(controller.availableUpdateVersion)

        controller.standardUserDriverWillHandleShowingUpdate(true, forUpdate: update, state: state)
        XCTAssertTrue(presentedUpdate)
    }
}

/// Creates a not-downloaded, scheduled state through Sparkle's public NSSecureCoding API.
private final class ScheduledUpdateStateDecoder: NSCoder {
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int { 0 }
    override func decodeBool(forKey key: String) -> Bool { false }
}
