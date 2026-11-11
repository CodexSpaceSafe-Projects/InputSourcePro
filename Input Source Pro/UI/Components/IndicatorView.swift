import SwiftUI

struct IndicatorView: NSViewControllerRepresentable {
    @EnvironmentObject var preferencesVM: PreferencesVM
    @EnvironmentObject var indicatorVM: IndicatorVM
    @EnvironmentObject var inputSourceVM: InputSourceVM

    private var config: IndicatorViewConfig {
        IndicatorViewConfig(
            inputSource: indicatorVM.state.inputSource,
            kind: preferencesVM.preferences.indicatorKind,
            size: preferencesVM.preferences.indicatorSize ?? .medium,
            bgColor: NSColor(preferencesVM.preferences.indicatorBackgroundColor),
            textColor: NSColor(preferencesVM.preferences.indicatorForgegroundColor),
            showsCapsLock: preferencesVM.preferences.isShowCapsLockStatus && indicatorVM.isCapsLockOn
        )
    }

    func makeNSViewController(context _: Context) -> IndicatorViewController {
        let controller = IndicatorViewController(layout: .preview)
        // Configure before SwiftUI's first measurement, including ideal-size queries.
        controller.prepare(config: config)
        controller.refresh()
        return controller
    }

    func updateNSViewController(_ controller: IndicatorViewController, context _: Context) {
        controller.prepare(config: config)
        controller.refresh()
    }

    @available(macOS 13.0, *)
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController controller: IndicatorViewController,
        context _: Context
    ) -> CGSize? {
        controller.previewSize(proposedWidth: proposal.width, proposedHeight: proposal.height)
    }
}

struct DumpIndicatorView: NSViewControllerRepresentable {
    let config: IndicatorViewConfig

    init(config: IndicatorViewConfig) {
        self.config = config
    }

    func makeNSViewController(context _: Context) -> IndicatorViewController {
        let controller = IndicatorViewController(layout: .preview)
        controller.prepare(config: config)
        controller.refresh()
        return controller
    }

    func updateNSViewController(_ controller: IndicatorViewController, context _: Context) {
        controller.prepare(config: config)
        controller.refresh()
    }

    @available(macOS 13.0, *)
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController controller: IndicatorViewController,
        context _: Context
    ) -> CGSize? {
        controller.previewSize(proposedWidth: proposal.width, proposedHeight: proposal.height)
    }
}
