import XCTest
@testable import Input_Source_Pro

final class ShortcutConflictTests: XCTestCase {
    private let abc = ShortcutAssignment(id: "abc", displayName: "ABC", shortcut: "⌘⇧A")
    private let pinyin = ShortcutAssignment(id: "pinyin", displayName: "Pinyin", shortcut: "⌘⇧B")
    private let functionKeys = ShortcutAssignment(
        id: "toggle-function-keys",
        displayName: "Toggle Function Keys",
        shortcut: "⌘⇧F"
    )

    private var assignments: [ShortcutAssignment<String>] {
        [abc, pinyin, functionKeys]
    }

    func testIgnoresTheRecorderThatIsBeingEdited() {
        XCTAssertNil(ShortcutConflict.owner(of: "⌘⇧A", excluding: "abc", in: assignments))
    }

    func testFindsTheExistingOwnerOfADuplicateShortcut() {
        let conflict = ShortcutConflict.owner(of: "⌘⇧A", excluding: "pinyin", in: assignments)

        XCTAssertEqual(conflict?.id, "abc")
        XCTAssertEqual(conflict?.displayName, "ABC")
    }

    func testStillConflictsWhenAnotherOwnerAlreadySharesTheShortcut() {
        let duplicateFunctionKeys = ShortcutAssignment(
            id: "toggle-function-keys",
            displayName: "Toggle Function Keys",
            shortcut: "⌘⇧A"
        )
        let conflict = ShortcutConflict.owner(
            of: "⌘⇧A",
            excluding: "abc",
            in: [abc, duplicateFunctionKeys]
        )

        XCTAssertEqual(conflict?.id, "toggle-function-keys")
    }

    func testFindsConflictAgainstFunctionKeysToggle() {
        let conflict = ShortcutConflict.owner(
            of: "⌘⇧F",
            excluding: "unrelated",
            in: assignments
        )

        XCTAssertEqual(conflict?.id, "toggle-function-keys")
        XCTAssertEqual(conflict?.displayName, "Toggle Function Keys")
    }

    func testAcceptsAUniqueShortcut() {
        let result = ShortcutConflict.resolve(
            proposed: "⌘⇧C",
            currentId: "pinyin",
            lastAccepted: pinyin.shortcut,
            assignments: assignments
        )

        XCTAssertEqual(result.accepted, "⌘⇧C")
        XCTAssertNil(result.conflictOwnerName)
    }

    func testRejectsAConflictAndKeepsThePreviousShortcut() {
        let result = ShortcutConflict.resolve(
            proposed: "⌘⇧A",
            currentId: "pinyin",
            lastAccepted: pinyin.shortcut,
            assignments: assignments
        )

        XCTAssertEqual(result.accepted, "⌘⇧B")
        XCTAssertEqual(result.conflictOwnerName, "ABC")
    }

    func testRejectsAConflictWhenTheRecorderWasEmpty() {
        let result = ShortcutConflict.resolve(
            proposed: "⌘⇧A",
            currentId: "new-row",
            lastAccepted: nil,
            assignments: assignments
        )

        XCTAssertNil(result.accepted)
        XCTAssertEqual(result.conflictOwnerName, "ABC")
    }

    func testClearingAShortcutIsNotAConflict() {
        let result = ShortcutConflict.resolve(
            proposed: nil as String?,
            currentId: "abc",
            lastAccepted: abc.shortcut,
            assignments: assignments
        )

        XCTAssertNil(result.accepted)
        XCTAssertNil(result.conflictOwnerName)
    }

    func testConflictMessageNamesTheExistingShortcut() {
        let message = ShortcutConflict.message(with: "ABC")

        XCTAssertTrue(message.contains("ABC"), "message should name the existing shortcut, got: \(message)")
        XCTAssertFalse(message.hasPrefix("**"), "message should be localized, got: \(message)")
    }

    func testPersistWritesRestoresCurrentAndReassertsOwnerShortcut() {
        let writes = ShortcutConflict.persistWrites(
            proposed: "⌘⇧A",
            currentId: "pinyin",
            decision: .init(accepted: "⌘⇧B", conflictOwnerName: "ABC"),
            assignments: assignments
        )

        XCTAssertEqual(
            writes,
            [
                ShortcutConflict.PersistWrite(id: "pinyin", shortcut: "⌘⇧B"),
                ShortcutConflict.PersistWrite(id: "abc", shortcut: "⌘⇧A")
            ]
        )
    }

    func testPersistWritesReassertsOwnerWhenCurrentHadNoShortcut() {
        let writes = ShortcutConflict.persistWrites(
            proposed: "⌘⇧A",
            currentId: "new-row",
            decision: .init(accepted: nil, conflictOwnerName: "ABC"),
            assignments: assignments
        )

        XCTAssertEqual(
            writes,
            [
                ShortcutConflict.PersistWrite(id: "new-row", shortcut: nil),
                ShortcutConflict.PersistWrite(id: "abc", shortcut: "⌘⇧A")
            ]
        )
    }

    func testPersistWritesNoOpsWhenThereIsNoConflict() {
        let writes = ShortcutConflict.persistWrites(
            proposed: "⌘⇧C",
            currentId: "pinyin",
            decision: .init(accepted: "⌘⇧C", conflictOwnerName: nil),
            assignments: assignments
        )

        XCTAssertTrue(writes.isEmpty)
    }

    func testModifierComboConflictsUseTheSameResolver() {
        let leftShift = ModifierCombo(keys: [.leftShift])
        let rightCommand = ModifierCombo(keys: [.rightCommand])
        let assignments = [
            ShortcutAssignment(id: "abc", displayName: "ABC", shortcut: leftShift)
        ]

        let result = ShortcutConflict.resolve(
            proposed: leftShift,
            currentId: "pinyin",
            lastAccepted: rightCommand,
            assignments: assignments
        )

        XCTAssertEqual(result.accepted, rightCommand)
        XCTAssertEqual(result.conflictOwnerName, "ABC")
    }

    func testSwitchingBackToKeyboardModeRejectsAReusedShortcutBeforeApplyingChanges() {
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .shift])
        let combo = ModifierCombo(keys: [.leftShift])
        var mode = ShortcutTriggerMode.singleModifier
        var savedCombo: ModifierCombo? = combo
        var registrationCount = 0

        let conflict = ShortcutConflict.updateMode(
            .keyboardShortcut,
            currentId: "abc",
            keyboardShortcut: shortcut,
            modifierCombo: savedCombo,
            keyboardAssignments: [.init(id: "pinyin", displayName: "Pinyin", shortcut: shortcut)],
            modifierAssignments: [],
            apply: {
                mode = $0
                savedCombo = nil
                registrationCount += 1
            }
        )

        XCTAssertEqual(conflict, "Pinyin")
        XCTAssertEqual(mode, .singleModifier)
        XCTAssertEqual(savedCombo, combo)
        XCTAssertEqual(registrationCount, 0)
    }

    func testModeChangeChecksTheFunctionKeysToggleForConflicts() {
        let shortcut = KeyboardShortcuts.Shortcut(.f, modifiers: [.command, .shift])
        let conflict = ShortcutConflict.updateMode(
            .keyboardShortcut,
            currentId: "switch-group",
            keyboardShortcut: shortcut,
            modifierCombo: nil,
            keyboardAssignments: [.init(
                id: PreferencesVM.functionKeysToggleShortcutId,
                displayName: "Toggle Function Keys",
                shortcut: shortcut
            )],
            modifierAssignments: [],
            apply: { _ in XCTFail("A conflicting mode must not be applied") }
        )

        XCTAssertEqual(conflict, "Toggle Function Keys")
    }

    func testModeChangeAllowsAnEmptyOrSelfOwnedKeyboardShortcut() {
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .shift])
        for savedShortcut in [nil, shortcut] {
            var mode = ShortcutTriggerMode.singleModifier
            let conflict = ShortcutConflict.updateMode(
                .keyboardShortcut,
                currentId: "abc",
                keyboardShortcut: savedShortcut,
                modifierCombo: nil,
                keyboardAssignments: [.init(id: "abc", displayName: "ABC", shortcut: shortcut)],
                modifierAssignments: [],
                apply: { mode = $0 }
            )

            XCTAssertNil(conflict)
            XCTAssertEqual(mode, .keyboardShortcut)
        }
    }

    func testSwitchingToModifierModeIgnoresTheInactiveKeyboardShortcut() {
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .shift])
        var mode = ShortcutTriggerMode.keyboardShortcut
        let conflict = ShortcutConflict.updateMode(
            .singleModifier,
            currentId: "abc",
            keyboardShortcut: shortcut,
            modifierCombo: nil,
            keyboardAssignments: [.init(id: "pinyin", displayName: "Pinyin", shortcut: shortcut)],
            modifierAssignments: [],
            apply: { mode = $0 }
        )

        XCTAssertNil(conflict)
        XCTAssertEqual(mode, .singleModifier)
    }

    func testSwitchingToModifierModeRejectsARetainedConflictingCombo() {
        let combo = ModifierCombo(keys: [.leftShift])
        let conflict = ShortcutConflict.updateMode(
            .singleModifier,
            currentId: PreferencesVM.functionKeysToggleShortcutId,
            keyboardShortcut: nil,
            modifierCombo: combo,
            keyboardAssignments: [],
            modifierAssignments: [.init(id: "switch-group", displayName: "ABC / Pinyin", shortcut: combo)],
            apply: { _ in XCTFail("A conflicting mode must not be applied") }
        )

        XCTAssertEqual(conflict, "ABC / Pinyin")
    }
}
