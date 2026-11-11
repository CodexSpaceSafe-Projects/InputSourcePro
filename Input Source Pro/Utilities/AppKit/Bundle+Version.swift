import AppKit

extension Bundle {
    var displayVersion: String {
        shortVersion
    }

    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var buildVersion: Int {
        Int(infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }
}
