import AppKit
import Darwin
import Security
import os

@MainActor
final class MigrationDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.onebutton.desktop", category: "FolderNameMigration")
    private var task: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        task = Task { await migrate() }
    }

    private func migrate() async {
        var migration: MigrationFileSystem?
        var parentStopped = false
        var renamed = false
        do {
            let helperURL = Bundle.main.bundleURL.standardizedFileURL
            let helpersDirectory = helperURL.deletingLastPathComponent()
            let contentsDirectory = helpersDirectory.deletingLastPathComponent()
            guard helpersDirectory.lastPathComponent == "Helpers",
                  contentsDirectory.lastPathComponent == "Contents" else {
                throw MigrationFailure.invalidLocation
            }
            let sourceURL = contentsDirectory.deletingLastPathComponent()
            let plan = try MigrationFileSystem(source: sourceURL)
            guard !sourceURL.pathComponents.contains("AppTranslocation"),
                  let bundle = Bundle(url: sourceURL),
                  bundle.bundleIdentifier == "com.onebutton.desktop",
                  bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "Folder In Bar",
                  bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Folder In Bar" else {
                throw MigrationFailure.invalidBundle
            }
            let sourceTeam = try signingTeam(at: sourceURL)
            guard sourceTeam == (try signingTeam(at: helperURL)) else { throw MigrationFailure.invalidSignature }

            // NSWorkspace ignores launch arguments from sandboxed callers; find only our enclosing app.
            let parents = NSRunningApplication.runningApplications(withBundleIdentifier: "com.onebutton.desktop").filter {
                !$0.isTerminated && $0.bundleURL?.standardizedFileURL == sourceURL
                    && $0.executableURL?.standardizedFileURL == sourceURL.appendingPathComponent("Contents/MacOS/Folder In Bar")
            }
            guard parents.count <= 1 else {
                throw MigrationFailure.invalidParent
            }
            migration = plan
            let deadline = ProcessInfo.processInfo.systemUptime + 15
            while let parent = parents.first {
                // NSRunningApplication may keep a stale isTerminated value in a background helper.
                if kill(parent.processIdentifier, 0) == -1, errno == ESRCH { break }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw MigrationFailure.parentTimeout }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            parentStopped = true
            try plan.preflight()
            try plan.rename()
            renamed = true
            try await launch(plan.destination)
        } catch {
            let failure = error as? MigrationFailure ?? .moveFailed
            logger.error("App name migration failed: \(failure.rawValue, privacy: .public)")
            if parentStopped, !renamed, failure != .sourceChanged, let migration {
                do {
                    try migration.verifySource()
                    guard try signingTeam(at: migration.source) == signingTeam(at: Bundle.main.bundleURL) else {
                        throw MigrationFailure.invalidSignature
                    }
                    try await launch(migration.source, arguments: ["--folder-name-migration-failed", failure.rawValue])
                    NSApp.terminate(nil)
                    return
                } catch {
                    logger.error("Could not reopen the original app after a failed migration")
                }
            }
            showFailure(failure, remainingURL: renamed ? migration?.destination : migration?.source)
        }
        NSApp.terminate(nil)
    }

    private func signingTeam(at url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw MigrationFailure.invalidSignature
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any],
              let team = information[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else {
            throw MigrationFailure.invalidSignature
        }
        return team
    }

    private func launch(_ url: URL, arguments: [String] = []) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw MigrationFailure.launchFailed
        }
    }

    private func showFailure(_ failure: MigrationFailure, remainingURL: URL?) {
        let alert = NSAlert()
        alert.messageText = "앱 파일 이름을 변경하지 못했습니다"
        switch failure {
        case .destinationExists:
            alert.informativeText = "같은 폴더에 Folder In Bar.app이 이미 있습니다. 기존 앱은 그대로 사용할 수 있습니다. 두 앱을 확인하신 뒤 중복 파일을 정리해 주세요."
        case .readOnly, .permissionDenied:
            alert.informativeText = "앱이 있는 폴더에 쓰기 권한이 없습니다. 기존 앱은 그대로 사용할 수 있으며 Finder에서 앱 파일 이름을 Folder In Bar.app으로 바꾸실 수 있습니다."
        case .parentTimeout:
            alert.informativeText = "실행 중인 앱이 종료되지 않아 파일 이름을 바꾸지 않았습니다. 앱을 종료한 뒤 다시 실행해 주세요."
        case .launchFailed:
            alert.messageText = "앱을 다시 열지 못했습니다"
            alert.informativeText = "Finder에서 앱을 다시 열어 주세요."
        default:
            alert.informativeText = "앱 파일을 안전하게 확인할 수 없어 작업을 중단했습니다. Finder에서 앱을 확인해 주세요."
        }
        if let remainingURL { alert.informativeText += "\n\n\(remainingURL.path)" }
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let application = NSApplication.shared
let delegate = MigrationDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
withExtendedLifetime(delegate) { application.run() }
