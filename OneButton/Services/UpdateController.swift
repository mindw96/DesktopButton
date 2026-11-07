import AppKit
import Combine
import Sparkle

/// Owns the updater for the lifetime of the menu bar application.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var availableUpdateVersion: String?

    var onWillPresentUpdate: (() -> Void)?

    private var controller: SPUStandardUpdaterController?

    init(isEnabled: Bool = true) {
        super.init()
        // UI tests must not create an updater, contact the feed, or change Sparkle preferences.
        guard isEnabled else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .assign(to: &$automaticallyDownloadsUpdates)
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard let controller, canCheckForUpdates else { return }
        onWillPresentUpdate?()
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater = controller?.updater,
              updater.automaticallyChecksForUpdates != enabled else { return }
        updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let updater = controller?.updater,
              updater.automaticallyDownloadsUpdates != enabled else { return }
        updater.automaticallyDownloadsUpdates = enabled
    }
}

// Sparkle invokes standard user-driver callbacks on the main thread, but the
// Objective-C delegate protocol does not annotate that actor requirement.
extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            onWillPresentUpdate?()
        } else {
            // The status item and popover present this reminder without stealing focus.
            availableUpdateVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableUpdateVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableUpdateVersion = nil
    }

    func standardUserDriverWillShowModalAlert() {
        onWillPresentUpdate?()
    }
}
