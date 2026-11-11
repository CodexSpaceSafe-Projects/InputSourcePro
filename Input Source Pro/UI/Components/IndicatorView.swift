import AppKit
import SwiftUI

struct IndicatorView: View {
    @EnvironmentObject var preferencesVM: PreferencesVM
    @EnvironmentObject var indicatorVM: IndicatorVM
    @EnvironmentObject var inputSourceVM: InputSourceVM

    var body: some View {
        DumpIndicatorView(config: IndicatorViewConfig(
            inputSource: indicatorVM.state.inputSource,
            kind: preferencesVM.preferences.indicatorKind,
            size: preferencesVM.preferences.indicatorSize ?? .medium,
            bgColor: NSColor(preferencesVM.preferences.indicatorBackgroundColor),
            textColor: NSColor(preferencesVM.preferences.indicatorForgegroundColor),
            showsCapsLock: preferencesVM.preferences.isShowCapsLockStatus && indicatorVM.isCapsLockOn
        ))
    }
}

/// A preview has one rendered indicator and a natural size. SwiftUI's surrounding
/// spacers, grids and alignment views own its placement; no window controller is needed.
struct DumpIndicatorView: NSViewRepresentable {
    let config: IndicatorViewConfig

    init(config: IndicatorViewConfig) {
        self.config = config
    }

    func makeNSView(context _: Context) -> IndicatorPreviewView {
        let view = IndicatorPreviewView(frame: .zero)
        view.configure(config: config)
        return view
    }

    func updateNSView(_ view: IndicatorPreviewView, context _: Context) {
        view.configure(config: config)
    }

    @available(macOS 13.0, *)
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: IndicatorPreviewView,
        context _: Context
    ) -> CGSize? {
        // Return the same ideal size for minimum, ideal and maximum proposals.
        // Expanding to a proposal here makes spacers/grid cells reserve space
        // that is not part of the rendered indicator, and breaks .fixedSize().
        nsView.naturalSize
    }
}

@MainActor
final class IndicatorPreviewView: NSViewHoverable {
    private var content: NSView?
    private(set) var naturalSize = NSSize.zero
    private var hasInitialSize = false

    func configure(config: IndicatorViewConfig) {
        content?.removeFromSuperview()
        content = config.render()
        naturalSize = content?.fittingSize ?? .zero

        // Start with real bounds before SwiftUI asks AppKit for its ideal size.
        // Later frame changes belong to SwiftUI; only update the child and ideal size.
        if !hasInitialSize {
            setFrameSize(naturalSize)
            hasInitialSize = true
        }
        if let content {
            content.translatesAutoresizingMaskIntoConstraints = true
            content.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            content.frame = contentFrame
            addSubview(content)
            content.layoutSubtreeIfNeeded()
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize { naturalSize }
    override var fittingSize: NSSize { naturalSize }

    override func layout() {
        super.layout()
        content?.frame = contentFrame
        content?.layoutSubtreeIfNeeded()
    }

    private var contentFrame: NSRect {
        NSRect(
            x: bounds.midX - naturalSize.width / 2,
            y: bounds.midY - naturalSize.height / 2,
            width: naturalSize.width,
            height: naturalSize.height
        )
    }
}
