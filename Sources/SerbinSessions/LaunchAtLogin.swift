import ServiceManagement

/// Login item for the running .app (does nothing useful for `swift run` builds, which have no bundle).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// `fail` receives a message when registration is refused (e.g. not running from a .app bundle).
    static func toggle(fail: (String) -> Void) {
        do {
            if isEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval {
                fail("Allow Serbin Sessions in System Settings > General > Login Items")
            }
        } catch {
            fail("Launch at login: \(error.localizedDescription)")
        }
    }
}
