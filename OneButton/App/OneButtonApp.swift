import Combine
import SwiftUI

@main
struct OneButtonApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var controller

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var store: DesktopStore!
    private var updateController: UpdateController!
    private var updateReminderObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var defaults = UserDefaults.standard
        var shouldStartUpdater = true
        #if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        shouldStartUpdater = !isUITesting && !isRunningUnitTests
        if isUITesting {
            let suite = "OneButton.UITests"
            defaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("--reset-test-state") {
                defaults.removePersistentDomain(forName: suite)
            }
        }
        #endif
        store = DesktopStore(defaults: defaults)
        updateController = UpdateController(isEnabled: shouldStartUpdater)
        updateController.onWillPresentUpdate = { [weak self] in
            self?.popover.performClose(nil)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: DesktopMenuView(
            store: store,
            updateController: updateController,
            defaults: defaults
        ) { [weak self] in
            self?.popover.performClose(nil)
        })

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "OneButton"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "OneButton 바탕화면")
            button.image?.isTemplate = true
            button.toolTip = "OneButton — 바탕화면 파일 열기"
            button.setAccessibilityLabel("OneButton 바탕화면")
            button.target = self
            button.action = #selector(togglePopover)
        }
        statusItem = item
        updateReminderObservation = updateController.$availableUpdateVersion.sink { [weak item] version in
            guard let button = item?.button else { return }
            let label = version.map { "OneButton 업데이트 \($0) 사용 가능" } ?? "OneButton 바탕화면"
            button.image = NSImage(systemSymbolName: version == nil ? "desktopcomputer" : "arrow.down.circle",
                                   accessibilityDescription: label)
            button.image?.isTemplate = true
            button.toolTip = version.map { "OneButton \($0) 업데이트 사용 가능" } ?? "OneButton — 바탕화면 파일 열기"
            button.setAccessibilityLabel(label)
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeKey()
        Task { await store.refresh() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}
