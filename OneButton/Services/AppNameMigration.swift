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
        alert.messageText = "앱 파일명을 변경하지 못했습니다"
        alert.informativeText = "Folder In Bar는 현재 이름으로 계속 사용할 수 있습니다. 앱을 종료한 뒤 Finder에서 OneButton.app을 Folder In Bar.app으로 바꿔 주세요. 같은 이름의 앱이 이미 있으면 먼저 확인해 주세요. 폴더 연결과 앱 설정은 유지됩니다."
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
