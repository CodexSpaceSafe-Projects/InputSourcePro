import AppKit
import ServiceManagement

/// Login-item registration uses the system service and never embeds another executable.
enum NativeLaunchAtLogin {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval: return true
            default: return false
            }
        }
        return false
    }

    static var requiresApproval: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .requiresApproval
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            if enabled { throw LoginItemError.unsupportedSystem }
            return
        }
        guard enabled != isEnabled else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// Stop a login item left by a previous installation before registering the main app.
    /// This only addresses this application's legacy bundle identifier.
    static func disableLegacyHelper() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        SMLoginItemSetEnabled((identifier + "-LaunchAtLoginHelper") as CFString, false)
    }

    private enum LoginItemError: LocalizedError {
        case unsupportedSystem

        var errorDescription: String? {
            "Launch at Login requires macOS 13 or later."
        }
    }
}
