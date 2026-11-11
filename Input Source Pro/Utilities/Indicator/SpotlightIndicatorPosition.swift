import AppKit

enum SpotlightIndicatorPosition {
    static func usesSearchFieldBounds(
        bundleIdentifier: String?,
        macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) -> Bool {
        macOSMajorVersion >= 27 && bundleIdentifier == "com.apple.campo"
    }

    static func searchFieldBounds(in application: UIElement) -> CGRect? {
        guard let field: UIElement = try? application.attribute(.focusedUIElement),
              let identifier: String = try? field.attribute("AXIdentifier"),
              identifier == "SpotlightSearchField",
              (try? field.role()) == .textField
        else { return nil }

        // The scroll area follows the visible search bar. The parent group and
        // window can cover the entire screen even when only that bar is visible.
        return UIElement.findInputAreaRect(field)
    }

    static func point(
        searchFieldBounds: CGRect,
        indicatorSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint? {
        let rect = searchFieldBounds
        guard rect.minX.isFinite, rect.minY.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0,
              visibleFrame.intersects(rect),
              !(rect.width > visibleFrame.width * 0.7 && rect.height > visibleFrame.height * 0.7),
              indicatorSize.width > 0, indicatorSize.height > 0,
              indicatorSize.width <= visibleFrame.width,
              indicatorSize.height <= visibleFrame.height
        else { return nil }

        let offset: CGFloat = 6
        let x = min(max(rect.minX, visibleFrame.minX), visibleFrame.maxX - indicatorSize.width)
        let above = CGPoint(x: x, y: rect.maxY + offset)
        if visibleFrame.contains(CGRect(origin: above, size: indicatorSize)) {
            return above
        }

        let below = CGPoint(x: x, y: rect.minY - offset - indicatorSize.height)
        return visibleFrame.contains(CGRect(origin: below, size: indicatorSize)) ? below : nil
    }
}
