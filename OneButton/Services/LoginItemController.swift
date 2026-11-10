import Combine
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?
    let allowsChanges: Bool
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    init(allowsChanges: Bool = true,
         readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.allowsChanges = allowsChanges
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        refresh()
    }

    func refresh() {
        status = allowsChanges ? readStatus() : .notRegistered
    }

    func setEnabled(_ enabled: Bool) {
        guard allowsChanges else { return }
        errorMessage = nil
        refresh()
        guard enabled != isRegistered else { return }
        do {
            if enabled { try register() } else { try unregister() }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        guard allowsChanges else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    func dismissError() { errorMessage = nil }
}
