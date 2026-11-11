import AppKit
import ApplicationServices
import XCTest
@testable import Input_Source_Pro

final class NativeAccessibilityTests: XCTestCase {
    func testNativeAXErrorsKeepDescriptiveSingleTokenDiagnostics() {
        XCTAssertEqual(String(describing: AXError.cannotComplete), "AXError.CannotComplete")
        XCTAssertEqual(String(describing: AXError.apiDisabled), "AXError.APIDisabled")
        for error: AXError in [.illegalArgument, .invalidUIElement, .attributeUnsupported,
                               .notificationUnsupported, .noValue] {
            XCTAssertFalse(String(describing: error).contains(" "))
        }
    }

    func testUnboxesSystemGeometryValues() throws {
        let point = CGPoint(x: 23, y: -4)
        let size = CGSize(width: 90, height: 31)
        let rect = CGRect(origin: point, size: size)
        XCTAssertEqual(try UIElement.decode(AXValue.point(point), as: CGPoint.self), point)
        XCTAssertEqual(try UIElement.decode(AXValue.size(size), as: CGSize.self), size)
        XCTAssertEqual(try UIElement.decode(AXValue.rect(rect), as: CGRect.self), rect)

        let range = try UIElement.decode(AXValue.range(CFRange(location: 4, length: 7)), as: CFRange.self)
        XCTAssertEqual(range.location, 4)
        XCTAssertEqual(range.length, 7)
    }

    func testMismatchedGeometryThrowsInsteadOfForceCasting() {
        XCTAssertThrowsError(try UIElement.decode(AXValue.size(.zero), as: CGRect.self)) { error in
            XCTAssertEqual(error as? AXError, .illegalArgument)
        }
    }

    func testSystemErrorValuesKeepTheOriginalCode() {
        XCTAssertThrowsError(try UIElement.decode(AXValue.error(.cannotComplete), as: Any.self)) { error in
            XCTAssertEqual(error as? AXError, .cannotComplete)
        }
    }

    func testWrapsNativeElementsOnlyWhenRequested() throws {
        let raw = AXUIElementCreateApplication(getpid())
        let wrapped = try UIElement.decode(raw, as: UIElement.self)
        XCTAssertTrue(CFEqual(wrapped.element, raw))
        let unwrapped = try UIElement.decode(raw, as: AXUIElement.self)
        XCTAssertTrue(CFEqual(unwrapped, raw))
    }

    func testChildrenCanBeReadAsNativeOrWrappedElements() throws {
        let raw = AXUIElementCreateApplication(getpid())
        let array = [raw] as CFArray
        let native = try UIElement.decode(array, as: [AXUIElement].self)
        let wrapped = try UIElement.decode(array, as: [UIElement].self)
        XCTAssertEqual(native.count, 1)
        XCTAssertEqual(wrapped.count, 1)
        XCTAssertTrue(CFEqual(native[0], raw))
        XCTAssertTrue(CFEqual(wrapped[0].element, raw))
    }

    func testElementEqualityAndHashFollowNativeIdentity() {
        let raw = AXUIElementCreateApplication(getpid())
        let first = UIElement(raw)
        let second = UIElement(raw)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
    }

    func testObserverRejectsInvalidProcessIDsBeforeAttaching() {
        for pid: pid_t in [-1, 0] {
            XCTAssertThrowsError(try Observer(processID: pid) { _, _, _ in }) { error in
                XCTAssertEqual(error as? AXError, .illegalArgument)
            }
            XCTAssertThrowsError(try Observer(processID: pid) { _, _, _, _ in }) { error in
                XCTAssertEqual(error as? AXError, .illegalArgument)
            }
        }
    }
}
