import Foundation

struct ShortcutAssignment<Shortcut: Equatable>: Equatable {
    let id: String
    let displayName: String
    let shortcut: Shortcut
}

enum ShortcutConflict {
    struct Decision<Shortcut: Equatable>: Equatable {
        let accepted: Shortcut?
        let conflictOwnerName: String?
    }

    struct PersistWrite<Shortcut: Equatable>: Equatable {
        let id: String
        let shortcut: Shortcut?
    }

    static func owner<Shortcut: Equatable>(
        of shortcut: Shortcut,
        excluding currentId: String,
        in assignments: [ShortcutAssignment<Shortcut>]
    ) -> ShortcutAssignment<Shortcut>? {
        assignments.first { assignment in
            assignment.id != currentId && assignment.shortcut == shortcut
        }
    }

    static func resolve<Shortcut: Equatable>(
        proposed: Shortcut?,
        currentId: String,
        lastAccepted: Shortcut?,
        assignments: [ShortcutAssignment<Shortcut>]
    ) -> Decision<Shortcut> {
        guard let proposed else {
            return Decision(accepted: nil, conflictOwnerName: nil)
        }

        if let owner = owner(of: proposed, excluding: currentId, in: assignments) {
            return Decision(accepted: lastAccepted, conflictOwnerName: owner.displayName)
        }

        return Decision(accepted: proposed, conflictOwnerName: nil)
    }

    static func message(with ownerName: String) -> String {
        String(format: "Conflicts with the %@ shortcut".i18n(), ownerName)
    }

    /// Validate before applying the mode, which may clear the modifier combo and
    /// register a previously inactive keyboard shortcut.
    static func updateMode(
        _ mode: ShortcutTriggerMode,
        currentId: String,
        keyboardShortcut: KeyboardShortcuts.Shortcut?,
        modifierCombo: ModifierCombo?,
        keyboardAssignments: [ShortcutAssignment<KeyboardShortcuts.Shortcut>],
        modifierAssignments: [ShortcutAssignment<ModifierCombo>],
        apply: (ShortcutTriggerMode) -> Void
    ) -> String? {
        let conflictOwnerName: String?
        switch mode {
        case .keyboardShortcut:
            conflictOwnerName = keyboardShortcut.flatMap {
                owner(of: $0, excluding: currentId, in: keyboardAssignments)?.displayName
            }
        case .singleModifier:
            conflictOwnerName = modifierCombo.flatMap {
                owner(of: $0, excluding: currentId, in: modifierAssignments)?.displayName
            }
        }

        guard conflictOwnerName == nil else { return conflictOwnerName }
        apply(mode)
        return nil
    }

    @MainActor
    static func keyboardAssignments(
        preferencesVM: PreferencesVM,
        groups: [HotKeyGroup]
    ) -> [ShortcutAssignment<KeyboardShortcuts.Shortcut>] {
        var assignments: [ShortcutAssignment<KeyboardShortcuts.Shortcut>] = []

        for inputSource in InputSource.sources {
            guard preferencesVM.shortcutMode(for: inputSource) == .keyboardShortcut else { continue }
            let id = inputSource.persistentIdentifier
            if let shortcut = KeyboardShortcuts.getShortcut(for: .init(id)) {
                assignments.append(.init(id: id, displayName: inputSource.name, shortcut: shortcut))
            }
        }

        for group in groups {
            guard preferencesVM.shortcutMode(for: group) == .keyboardShortcut,
                  let id = group.id,
                  let shortcut = KeyboardShortcuts.getShortcut(for: .init(id))
            else { continue }
            assignments.append(.init(id: id, displayName: displayName(for: group), shortcut: shortcut))
        }

        let functionKeysId = PreferencesVM.functionKeysToggleShortcutId
        if preferencesVM.functionKeysToggleMode() == .keyboardShortcut,
           let shortcut = KeyboardShortcuts.getShortcut(for: .init(functionKeysId))
        {
            assignments.append(.init(
                id: functionKeysId,
                displayName: "Toggle Function Keys".i18n(),
                shortcut: shortcut
            ))
        }

        return assignments
    }

    @MainActor
    static func modifierAssignments(
        preferencesVM: PreferencesVM,
        groups: [HotKeyGroup]
    ) -> [ShortcutAssignment<ModifierCombo>] {
        var assignments: [ShortcutAssignment<ModifierCombo>] = []

        for inputSource in InputSource.sources {
            guard preferencesVM.shortcutMode(for: inputSource) == .singleModifier,
                  let combo = preferencesVM.modifierCombo(for: inputSource)
            else { continue }
            assignments.append(.init(
                id: inputSource.persistentIdentifier,
                displayName: inputSource.name,
                shortcut: combo
            ))
        }

        for group in groups {
            guard preferencesVM.shortcutMode(for: group) == .singleModifier,
                  let id = group.id,
                  let combo = preferencesVM.modifierCombo(for: group)
            else { continue }
            assignments.append(.init(id: id, displayName: displayName(for: group), shortcut: combo))
        }

        if preferencesVM.functionKeysToggleMode() == .singleModifier,
           let combo = preferencesVM.functionKeysToggleCombo()
        {
            assignments.append(.init(
                id: PreferencesVM.functionKeysToggleShortcutId,
                displayName: "Toggle Function Keys".i18n(),
                shortcut: combo
            ))
        }

        return assignments
    }

    @MainActor
    private static func displayName(for group: HotKeyGroup) -> String {
        let names = group.inputSources.map(\.name).joined(separator: " / ")
        return names.isEmpty ? "Shortcut".i18n() : names
    }

    static func persistWrites<Shortcut: Equatable>(
        proposed: Shortcut?,
        currentId: String,
        decision: Decision<Shortcut>,
        assignments: [ShortcutAssignment<Shortcut>]
    ) -> [PersistWrite<Shortcut>] {
        guard decision.conflictOwnerName != nil else { return [] }

        var writes = [PersistWrite(id: currentId, shortcut: decision.accepted)]

        if let proposed,
           let owner = owner(of: proposed, excluding: currentId, in: assignments)
        {
            writes.append(PersistWrite(id: owner.id, shortcut: owner.shortcut))
        }

        return writes
    }

    /// KeyboardShortcuts saves the new shortcut before `onChange` runs. If that
    /// shortcut is already owned by another recorder, restore the previous value
    /// and re-assert the owner's registration so Carbon doesn't drop it.
    @MainActor
    static func persistKeyboardShortcut(
        proposed: KeyboardShortcuts.Shortcut?,
        currentId: String,
        decision: Decision<KeyboardShortcuts.Shortcut>,
        assignments: [ShortcutAssignment<KeyboardShortcuts.Shortcut>]
    ) {
        for write in persistWrites(
            proposed: proposed,
            currentId: currentId,
            decision: decision,
            assignments: assignments
        ) {
            KeyboardShortcuts.setShortcut(write.shortcut, for: .init(write.id))
        }
    }
}
