import AppKit
import Combine

@MainActor
final class AlwaysOnIndicatorWindowController: FloatWindowController {
    private var cancelBag = CancelBag()
    private(set) var indicatorView: NSView?
    private var leadingConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

    var position: CGPoint? {
        didSet { updateVisibility() }
    }

    var isDefaultIndicatorVisible = false {
        didSet { updateVisibility() }
    }

    func observe(
        configs: AnyPublisher<IndicatorViewConfig, Never>,
        positions: AnyPublisher<CGPoint?, Never>
    ) {
        cancelBag.cancel()

        configs
            .sink { [weak self] in self?.update(config: $0) }
            .store(in: cancelBag)

        positions
            .sink { [weak self] in self?.position = $0 }
            .store(in: cancelBag)
    }

    func update(config: IndicatorViewConfig) {
        IndicatorDiagnostics.record("alwaysOn.content source=\(config.inputSource.persistentIdentifier) capsLock=\(config.showsCapsLock)")
        guard let view = config.renderAlwaysOn() else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            let size = view.fittingSize
            let container = NSView()
            container.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            let leading = view.leadingAnchor.constraint(equalTo: container.leadingAnchor)
            let bottom = view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            NSLayoutConstraint.activate([
                leading, bottom,
                view.widthAnchor.constraint(equalToConstant: size.width),
                view.heightAnchor.constraint(equalToConstant: size.height),
            ])
            leadingConstraint = leading
            bottomConstraint = bottom
            indicatorView = view
            window?.contentView = container
            window?.setContentSize(size)
            updateVisibility()
        }
    }

    func reorderOnActiveSpace() {
        guard window?.isVisible == true else { return }

        deactive()
        active()
    }

    private func updateVisibility() {
        IndicatorDiagnostics.record("alwaysOn.visibility point=\(String(describing: position)) defaultVisible=\(isDefaultIndicatorVisible) frame=\(String(describing: window?.frame))")
        guard let position = position,
              let window = window,
              let indicatorView = indicatorView
        else {
            deactive()
            return
        }

        let size = indicatorView.fittingSize
        let origin = CGPoint(x: position.x - size.width / 2, y: position.y)
        let layout = PixelAlignedWindowLayout(
            origin: NSScreen.pixelAlignedOrigin(origin, near: position), size: size
        )
        leadingConstraint?.constant = layout.contentOffset.x
        bottomConstraint?.constant = -layout.contentOffset.y
        window.setFrame(layout.frame, display: true)
        window.contentView?.layoutSubtreeIfNeeded()

        if isDefaultIndicatorVisible {
            IndicatorDiagnostics.record("alwaysOn.hidden reason=default-visible")
            deactive()
        } else if !window.isVisible {
            active()
        }
    }
}
