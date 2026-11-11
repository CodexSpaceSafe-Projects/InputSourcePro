import AppKit
import Carbon

/// The app's shortcut storage, global hotkeys and recorder, implemented with macOS APIs.
/// The namespace and stored JSON keys preserve existing user shortcuts and backups.
enum KeyboardShortcuts {
    struct Name: Hashable, RawRepresentable {
        let rawValue: String

        init(_ rawValue: String) { self.rawValue = rawValue }
        init(rawValue: String) { self.rawValue = rawValue }
    }

    struct Key: Hashable, RawRepresentable {
        let rawValue: Int

        init(rawValue: Int) { self.rawValue = rawValue }

        static let a = Self(rawValue: kVK_ANSI_A)
        static let f = Self(rawValue: kVK_ANSI_F)
    }

    struct Shortcut: Hashable, Codable {
        let carbonKeyCode: Int
        let carbonModifiers: Int

        var key: Key? { (0...Int(UInt16.max)).contains(carbonKeyCode) ? Key(rawValue: carbonKeyCode) : nil }
        var modifiers: NSEvent.ModifierFlags {
            var result: NSEvent.ModifierFlags = []
            if carbonModifiers & cmdKey != 0 { result.insert(.command) }
            if carbonModifiers & optionKey != 0 { result.insert(.option) }
            if carbonModifiers & controlKey != 0 { result.insert(.control) }
            if carbonModifiers & shiftKey != 0 { result.insert(.shift) }
            return result
        }

        init(_ key: Key, modifiers: NSEvent.ModifierFlags = []) {
            self.init(carbonKeyCode: key.rawValue, carbonModifiers: Self.carbonModifiers(for: modifiers))
        }

        init(carbonKeyCode: Int, carbonModifiers: Int = 0) {
            self.carbonKeyCode = carbonKeyCode
            // Caps Lock, numeric-pad and device-specific bits do not identify a hotkey.
            self.carbonModifiers = carbonModifiers & (cmdKey | optionKey | controlKey | shiftKey)
        }

        private enum CodingKeys: String, CodingKey { case carbonKeyCode, carbonModifiers }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let code = try values.decode(Int.self, forKey: .carbonKeyCode)
            guard (0...Int(UInt16.max)).contains(code) else {
                throw DecodingError.dataCorruptedError(forKey: .carbonKeyCode, in: values,
                                                       debugDescription: "Invalid virtual key code")
            }
            self.init(carbonKeyCode: code, carbonModifiers: try values.decode(Int.self, forKey: .carbonModifiers))
        }

        static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> Int {
            var result = 0
            if flags.contains(.command) { result |= cmdKey }
            if flags.contains(.option) { result |= optionKey }
            if flags.contains(.control) { result |= controlKey }
            if flags.contains(.shift) { result |= shiftKey }
            return result
        }

        var displayString: String {
            let flags = modifiers
            return (flags.contains(.control) ? "⌃" : "")
                + (flags.contains(.option) ? "⌥" : "")
                + (flags.contains(.shift) ? "⇧" : "")
                + (flags.contains(.command) ? "⌘" : "")
                + Self.keyLabel(carbonKeyCode)
        }

        private static func keyLabel(_ code: Int) -> String {
            let symbols = [kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
                           kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
                           kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
                           kVK_DownArrow: "↓", kVK_UpArrow: "↑", kVK_ANSI_KeypadEnter: "⌤"]
            if let symbol = symbols[code] { return symbol }
            let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                                kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                                kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
            if let index = functionKeys.firstIndex(of: code) { return "F\(index + 1)" }
            // Translate the physical key using the user's ASCII-capable layout, not a fixed US layout.
            if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
               let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
                if let bytes = CFDataGetBytePtr(data) {
                    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
                    var deadKeyState: UInt32 = 0
                    var characters = [UniChar](repeating: 0, count: 8)
                    var count: UniCharCount = 0
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                                &deadKeyState, UniCharCount(characters.count), &count, &characters)
                    if status == noErr, count > 0 {
                        return String(utf16CodeUnits: characters, count: Int(count)).uppercased()
                    }
                }
            }
            return "Key \(code)"
        }
    }

    private static let changedNotification = Notification.Name("InputSourceProNativeShortcutChanged")

    static func getShortcut(for name: Name) -> Shortcut? {
        let key = "KeyboardShortcuts_" + name.rawValue
        // Previous versions store JSON as a string. Accept Data as well for local migrations.
        let value = UserDefaults.standard.object(forKey: key)
        let data = (value as? String)?.data(using: .utf8) ?? value as? Data
        guard let data else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    @MainActor
    static func setShortcut(_ shortcut: Shortcut?, for name: Name) {
        let key = "KeyboardShortcuts_" + name.rawValue
        if let shortcut, let data = try? JSONEncoder().encode(shortcut),
           let value = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        Registry.shared.register(name)
        NotificationCenter.default.post(name: changedNotification, object: name.rawValue)
    }

    @MainActor
    static func reset(_ names: [Name]) {
        names.forEach { setShortcut(nil, for: $0) }
    }

    @MainActor
    static func onKeyUp(for name: Name, action: @escaping () -> Void) {
        Registry.shared.handlers[name, default: []].append(action)
        Registry.shared.register(name)
    }

    @MainActor
    static func removeAllHandlers() {
        Registry.shared.unregisterAll()
        Registry.shared.handlers.removeAll()
    }

    /// Carbon hotkeys deliver only explicitly registered combinations. They do not monitor typed text.
    @MainActor
    private final class Registry {
        static let shared = Registry()
        static let signature: OSType = 0x4953504B // ISPK
        var handlers: [Name: [() -> Void]] = [:]
        private var references: [Name: EventHotKeyRef] = [:]
        private var names: [UInt32: Name] = [:]
        private var identifiers: [Name: UInt32] = [:]
        private var nextIdentifier: UInt32 = 1
        private var eventHandler: EventHandlerRef?
        private var recordingCount = 0

        private init() {}

        func register(_ name: Name) {
            if let reference = references.removeValue(forKey: name) { UnregisterEventHotKey(reference) }
            if let identifier = identifiers.removeValue(forKey: name) { names.removeValue(forKey: identifier) }
            guard recordingCount == 0, handlers[name]?.isEmpty == false,
                  let shortcut = getShortcut(for: name), shortcut.key != nil else { return }
            if eventHandler == nil {
                var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
                let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                    guard let event else { return OSStatus(eventNotHandledErr) }
                    var identifier = EventHotKeyID()
                    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                                   EventParamType(typeEventHotKeyID), nil,
                                                   ByteCount(MemoryLayout<EventHotKeyID>.size), nil, &identifier)
                    guard status == noErr, identifier.signature == 0x4953504B else {
                        return OSStatus(eventNotHandledErr)
                    }
                    let id = identifier.id
                    DispatchQueue.main.async { Registry.shared.dispatch(id) }
                    return noErr
                }, 1, &type, nil, &eventHandler)
                guard status == noErr else {
                    NSLog("Could not install shortcut handler (OSStatus %d)", status)
                    return
                }
            }
            let identifier = nextIdentifier
            nextIdentifier &+= 1
            if nextIdentifier == 0 || nextIdentifier == UInt32.max { nextIdentifier = 1 }
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.carbonKeyCode), UInt32(shortcut.carbonModifiers),
                                             EventHotKeyID(signature: Self.signature, id: identifier),
                                             GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                NSLog("Could not register shortcut %@ (OSStatus %d)", name.rawValue, status)
                return
            }
            references[name] = reference
            identifiers[name] = identifier
            names[identifier] = name
        }

        private func dispatch(_ identifier: UInt32) {
            guard recordingCount == 0, let name = names[identifier] else { return }
            handlers[name]?.forEach { $0() }
        }

        func unregisterAll() {
            references.values.forEach { UnregisterEventHotKey($0) }
            references.removeAll()
            identifiers.removeAll()
            names.removeAll()
        }

        func beginRecording() {
            recordingCount += 1
            unregisterAll()
        }

        func endRecording() {
            recordingCount = max(recordingCount - 1, 0)
            guard recordingCount == 0 else { return }
            handlers.keys.sorted { $0.rawValue < $1.rawValue }.forEach(register)
        }

        func canRegister(_ shortcut: Shortcut) -> Bool {
            guard shortcut.key != nil else { return false }
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.carbonKeyCode), UInt32(shortcut.carbonModifiers),
                                             EventHotKeyID(signature: Self.signature, id: UInt32.max),
                                             GetApplicationEventTarget(), 0, &reference)
            if let reference { UnregisterEventHotKey(reference) }
            return status == noErr
        }
    }

    final class RecorderCocoa: NSButton {
        var shortcutName: Name {
            didSet { if shortcutName != oldValue { finishRecording(); refreshTitle() } }
        }
        private let onChange: (Shortcut?) -> Void
        private var recording = false
        private var monitor: Any?
        private var observation: NSObjectProtocol?

        init(for name: Name, onChange: @escaping (Shortcut?) -> Void) {
            shortcutName = name
            self.onChange = onChange
            super.init(frame: .zero)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(startRecording)
            toolTip = "Click to record a shortcut. Press Delete to clear, or Escape to cancel."
            setAccessibilityLabel(NSLocalizedString("Keyboard shortcut", comment: "Shortcut recorder accessibility label"))
            observation = NotificationCenter.default.addObserver(forName: changedNotification, object: nil,
                                                                 queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.refreshTitle() }
            }
            refreshTitle()
        }

        required init?(coder: NSCoder) { return nil }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let observation { NotificationCenter.default.removeObserver(observation) }
            if recording { DispatchQueue.main.async { Registry.shared.endRecording() } }
        }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize {
            let size = super.intrinsicContentSize
            return NSSize(width: max(size.width, 125), height: max(size.height, 24))
        }

        override func resignFirstResponder() -> Bool {
            finishRecording()
            return super.resignFirstResponder()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { finishRecording() }
            super.viewWillMove(toWindow: newWindow)
        }

        @objc private func startRecording() {
            guard !recording, window?.makeFirstResponder(self) == true else { return }
            recording = true
            Registry.shared.beginRecording()
            title = NSLocalizedString("Press shortcut…", comment: "Shortcut recorder prompt")
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.recording, event.window === self.window else { return event }
                self.record(event)
                return nil
            }
        }

        override func keyDown(with event: NSEvent) {
            if recording { record(event) }
            else { super.keyDown(with: event) }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            record(event)
            return true
        }

        private func record(_ event: NSEvent) {
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if flags.isEmpty, event.keyCode == UInt16(kVK_Escape) { finishRecording(); return }
            if flags.isEmpty, [kVK_Delete, kVK_ForwardDelete].contains(Int(event.keyCode)) {
                save(nil)
                return
            }
            if flags.isEmpty, event.keyCode == UInt16(kVK_Tab) {
                finishRecording()
                window?.selectNextKeyView(self)
                return
            }
            let functionCodes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                                 kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                                 kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
            guard !flags.intersection([.command, .option, .control]).isEmpty
                    || functionCodes.contains(Int(event.keyCode)) else { NSSound.beep(); return }
            let shortcut = Shortcut(carbonKeyCode: Int(event.keyCode), carbonModifiers: Shortcut.carbonModifiers(for: flags))
            guard Registry.shared.canRegister(shortcut) else {
                title = NSLocalizedString("Shortcut unavailable", comment: "Shortcut is reserved by another application")
                NSSound.beep()
                return
            }
            save(shortcut)
        }

        private func save(_ shortcut: Shortcut?) {
            setShortcut(shortcut, for: shortcutName)
            onChange(shortcut)
            finishRecording()
        }

        private func finishRecording() {
            guard recording else { return }
            recording = false
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            Registry.shared.endRecording()
            refreshTitle()
        }

        private func refreshTitle() {
            guard !recording else { return }
            title = getShortcut(for: shortcutName)?.displayString
                ?? NSLocalizedString("Record Shortcut", comment: "Button to record a keyboard shortcut")
            invalidateIntrinsicContentSize()
        }
    }
}
