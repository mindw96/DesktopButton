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
    #if !APP_STORE
    private var updateController: UpdateController!
    private var updateReminderObservation: AnyCancellable?
    #endif
    private var loginItemController: LoginItemController!
    private var dockIconController: DockIconController!
    private var popoverSize: PopoverSize!
    private var sizeObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var defaults = UserDefaults.standard
        var allowsSystemServices = true
        #if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        allowsSystemServices = !isUITesting && !isRunningUnitTests
        if isUITesting {
            let suite = "OneButton.UITests"
            defaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.arguments.contains("--reset-test-state") {
                defaults.removePersistentDomain(forName: suite)
            }
        }
        #endif
        store = DesktopStore(defaults: defaults)
        popoverSize = PopoverSize(defaults: defaults)
        loginItemController = LoginItemController(allowsChanges: allowsSystemServices)
        dockIconController = DockIconController(defaults: defaults)
        #if !APP_STORE
        updateController = UpdateController(isEnabled: allowsSystemServices)
        updateController.onWillPresentUpdate = { [weak self] in
            self?.popover.performClose(nil)
        }
        #endif
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        #if APP_STORE
        let menu = DesktopMenuView(
            store: store,
            loginItemController: loginItemController,
            dockIconController: dockIconController,
            popoverSize: popoverSize,
            defaults: defaults
        ) { [weak self] in
            self?.popover.performClose(nil)
        }
        #else
        let menu = DesktopMenuView(
            store: store,
            updateController: updateController,
            loginItemController: loginItemController,
            dockIconController: dockIconController,
            popoverSize: popoverSize,
            defaults: defaults
        ) { [weak self] in
            self?.popover.performClose(nil)
        }
        #endif
        popover.contentViewController = NSHostingController(rootView: menu)
        sizeObservation = popoverSize.$size.sink { [weak self] size in
            self?.popover.contentSize = size
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "OneButton"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder In Bar 폴더")
            button.image?.isTemplate = true
            button.toolTip = "Folder In Bar — 연결한 폴더 열기"
            button.setAccessibilityLabel("Folder In Bar 폴더")
            button.target = self
            button.action = #selector(togglePopover)
        }
        statusItem = item
        #if !APP_STORE
        updateReminderObservation = updateController.$availableUpdateVersion.sink { [weak item] version in
            guard let button = item?.button else { return }
            let label = version.map { "Folder In Bar 업데이트 \($0) 사용 가능" } ?? "Folder In Bar 폴더"
            button.image = NSImage(systemSymbolName: version == nil ? "folder" : "arrow.down.circle",
                                   accessibilityDescription: label)
            button.image?.isTemplate = true
            button.toolTip = version.map { "Folder In Bar \($0) 업데이트 사용 가능" } ?? "Folder In Bar — 연결한 폴더 열기"
            button.setAccessibilityLabel(label)
        }
        if allowsSystemServices {
            AppNameMigration.runIfNeeded(defaults: defaults, loginItem: loginItemController)
        }
        #endif
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !popover.isShown, let button = statusItem?.button else { return }
        if let window = button.window, let screen = window.screen {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            let visible = screen.visibleFrame
            popoverSize.fit(in: CGSize(width: visible.width - 24, height: visible.height - 60),
                            fromLeadingEdge: anchor.midX >= visible.midX)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func popoverDidShow(_ notification: Notification) {
        loginItemController.refresh()
        if let window = popover.contentViewController?.view.window {
            // Keep the popover available above other apps' fullscreen windows after Dock policy changes.
            window.collectionBehavior.subtract([.moveToActiveSpace, .primary, .auxiliary,
                                                .fullScreenPrimary, .fullScreenNone])
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary])
            window.makeKey()
        }
        Task { await store.refresh() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItemController?.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}
