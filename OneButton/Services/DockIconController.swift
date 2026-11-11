import AppKit
import Combine

@MainActor
final class DockIconController: ObservableObject {
    @Published private(set) var showsIcon: Bool
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let applyPolicy: (NSApplication.ActivationPolicy) -> Bool

    init(defaults: UserDefaults,
         readPolicy: () -> NSApplication.ActivationPolicy = { NSApp.activationPolicy() },
         applyPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool = { NSApp.setActivationPolicy($0) }) {
        self.defaults = defaults
        self.applyPolicy = applyPolicy
        let currentPolicy = readPolicy()
        showsIcon = currentPolicy == .regular
        let saved = defaults.bool(forKey: "showDockIcon")
        let requestedPolicy: NSApplication.ActivationPolicy = saved ? .regular : .accessory
        if currentPolicy == requestedPolicy || applyPolicy(requestedPolicy) {
            showsIcon = saved
        } else {
            errorMessage = String(localized: "Could not change Dock icon visibility. Please try again.")
        }
    }

    func setShowsIcon(_ visible: Bool) {
        errorMessage = nil
        guard visible != showsIcon else { return }
        guard applyPolicy(visible ? .regular : .accessory) else {
            errorMessage = String(localized: "Could not change Dock icon visibility. Please try again.")
            return
        }
        showsIcon = visible
        defaults.set(visible, forKey: "showDockIcon")
    }

    func dismissError() { errorMessage = nil }
}
