import ServiceManagement
import XCTest
@testable import OneButton

@MainActor
final class LoginItemControllerTests: XCTestCase {
    func testRegistrationAndRemovalFollowSystemStatus() {
        var status = SMAppService.Status.notRegistered
        var registrations = 0
        var removals = 0
        let controller = LoginItemController(readStatus: { status }, register: {
            registrations += 1
            status = .enabled
        }, unregister: {
            removals += 1
            status = .notRegistered
        })
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(registrations, 0)
        controller.setEnabled(true)
        XCTAssertEqual(controller.status, .enabled)
        controller.setEnabled(true)
        XCTAssertEqual(registrations, 1)
        controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(removals, 1)
        XCTAssertNil(controller.errorMessage)
    }

    func testPendingApprovalIsDistinctAndCanBeCancelledWithoutRegisteringAgain() {
        var status = SMAppService.Status.requiresApproval
        let controller = LoginItemController(readStatus: { status }, register: {
            XCTFail("A pending login item must not be registered again")
        }, unregister: { status = .notRegistered })
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(controller.status, .requiresApproval)
        controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
    }

    func testFailedRegistrationPreservesRealStateAndReportsError() {
        let controller = LoginItemController(readStatus: { .notRegistered }, register: {
            throw NSError(domain: "LoginItemTest", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Registration denied"])
        })
        controller.setEnabled(true)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(controller.errorMessage, "Registration denied")
        controller.dismissError()
        XCTAssertNil(controller.errorMessage)
    }

    func testFailedRemovalDoesNotClaimLoginItemIsDisabled() {
        let controller = LoginItemController(readStatus: { .enabled }, unregister: {
            throw NSError(domain: "LoginItemTest", code: 2)
        })
        controller.setEnabled(false)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testRefreshReflectsChangesMadeOutsideTheApp() {
        var status = SMAppService.Status.enabled
        let controller = LoginItemController(readStatus: { status })
        status = .requiresApproval
        controller.refresh()
        XCTAssertEqual(controller.status, .requiresApproval)
        status = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.isRegistered)
    }

    func testUIAndUnitTestModeNeverReadsOrChangesSystemLoginItems() {
        let controller = LoginItemController(allowsChanges: false, readStatus: {
            XCTFail("Test mode must not read system login items")
            return .enabled
        }, register: {
            XCTFail("Test mode must not register login items")
        }, unregister: {
            XCTFail("Test mode must not unregister login items")
        })
        controller.setEnabled(true)
        controller.setEnabled(false)
        controller.refresh()
        XCTAssertFalse(controller.isRegistered)
        XCTAssertFalse(controller.allowsChanges)
    }
}
