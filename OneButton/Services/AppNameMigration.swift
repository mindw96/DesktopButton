import AppKit

@MainActor
enum AppNameMigration {
    static let pendingKey = "pendingAppNameMigration"

    static func runIfNeeded(defaults: UserDefaults, loginItem: LoginItemController) {
        let appURL = Bundle.main.bundleURL.standardizedFileURL
        let restoreLogin = consumeLoginRestore(defaults: defaults, appURL: appURL)
        if restoreLogin { loginItem.setEnabled(true) }

        if ProcessInfo.processInfo.arguments.contains("--folder-name-migration-failed") {
            showFailure()
            return
        }
        guard appURL.lastPathComponent == "OneButton.app" else { return }
        let helperURL = appURL.appendingPathComponent("Contents/Helpers/FolderNameMigrationHelper.app")
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            showFailure()
            return
        }

        loginItem.refresh()
        defaults.set([
            "destination": appURL.deletingLastPathComponent().appendingPathComponent("Folder In Bar.app").path,
            "enabled": loginItem.status == .enabled,
            "createdAt": Date().timeIntervalSince1970
        ], forKey: pendingKey)
        // Persist before this process exits and the helper relaunches the renamed app.
        defaults.synchronize()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
                NSApp.terminate(nil)
            } catch {
                defaults.removeObject(forKey: pendingKey)
                showFailure()
            }
        }
    }

    static func consumeLoginRestore(defaults: UserDefaults, appURL: URL, now: Date = Date()) -> Bool {
        guard let pending = defaults.dictionary(forKey: pendingKey) else { return false }
        defaults.removeObject(forKey: pendingKey)
        guard appURL.lastPathComponent == "Folder In Bar.app",
              pending["destination"] as? String == appURL.standardizedFileURL.path,
              pending["enabled"] as? Bool == true,
              let timestamp = pending["createdAt"] as? TimeInterval,
              (0...300).contains(now.timeIntervalSince1970 - timestamp) else { return false }
        return true
    }

    private static func showFailure() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Could Not Rename the App")
        alert.informativeText = String(localized: "You can continue using Folder In Bar with its current filename. Quit the app, then rename OneButton.app to Folder In Bar.app in Finder. If an app with that name already exists, check it first. Your folder connection and app settings will be preserved.")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
