import AppKit
import Combine

class FocusAwareTextField: NSTextField {
    let focus$ = PassthroughSubject<Bool, Never>()

    override func becomeFirstResponder() -> Bool {
        focus$.send(true)
        return super.becomeFirstResponder()
    }
}
