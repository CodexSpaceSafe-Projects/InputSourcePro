import AppKit
import Carbon
import XCTest
@testable import Input_Source_Pro

final class NativeKeyboardShortcutsTests: XCTestCase {
    func testDecodesExistingShortcutBackupAndNormalizesUnrelatedModifierBits() throws {
        let data = Data("{\"carbonKeyCode\":0,\"carbonModifiers\":66304}".utf8)
        let shortcut = try JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: data)

        XCTAssertEqual(shortcut, .init(.a, modifiers: [.command, .shift]))
        XCTAssertEqual(shortcut.carbonModifiers, cmdKey | shiftKey)
    }

    func testBackupEncodingRetainsExistingFieldNamesAndRoundTrips() throws {
        let original = KeyboardShortcuts.Shortcut(.f, modifiers: [.command, .control, .option])
        let data = try JSONEncoder().encode(original)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])

        XCTAssertEqual(Set(fields.keys), ["carbonKeyCode", "carbonModifiers"])
        XCTAssertEqual(fields["carbonKeyCode"], kVK_ANSI_F)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: data), original)
    }

    func testRejectsMalformedVirtualKeyCodesBeforeCallingCarbon() {
        for code in [-1, Int(UInt16.max) + 1] {
            let data = Data("{\"carbonKeyCode\":\(code),\"carbonModifiers\":256}".utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: data))
        }
    }

    func testReadsPreviouslyStoredJSONAndDisabledValue() throws {
        let name = KeyboardShortcuts.Name("native-test-\(UUID().uuidString)")
        let defaultsKey = "KeyboardShortcuts_" + name.rawValue
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }
        UserDefaults.standard.set("{\"carbonKeyCode\":0,\"carbonModifiers\":768}", forKey: defaultsKey)

        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: name), .init(.a, modifiers: [.command, .shift]))

        UserDefaults.standard.set(false, forKey: defaultsKey)
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: name))
    }

    @MainActor
    func testResetOnlyClearsRequestedShortcutAndPreservesOtherAssignments() {
        let first = KeyboardShortcuts.Name("native-test-\(UUID().uuidString)")
        let second = KeyboardShortcuts.Name("native-test-\(UUID().uuidString)")
        defer { KeyboardShortcuts.reset([first, second]) }
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .shift])
        KeyboardShortcuts.setShortcut(shortcut, for: first)
        KeyboardShortcuts.setShortcut(shortcut, for: second)

        KeyboardShortcuts.reset([first])

        XCTAssertNil(KeyboardShortcuts.getShortcut(for: first))
        XCTAssertEqual(KeyboardShortcuts.getShortcut(for: second), shortcut)
    }
}
