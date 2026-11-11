import AppKit

extension URL {
    static let newtab = URL(string: "isp://newtab")!

    func bundleId() -> String {
        Bundle(url: self)?.bundleIdentifier ?? dataRepresentation.md5()
    }

    func removeFragment() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)

        components?.fragment = nil

        return components?.url ?? self
    }
}
