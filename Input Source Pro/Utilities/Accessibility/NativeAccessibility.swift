import AppKit
import ApplicationServices

// These names describe the Accessibility attributes used by this application.
// All operations below call the system AX APIs directly; no package is loaded.
enum Attribute: String, Hashable {
    case role = "AXRole"
    case subrole = "AXSubrole"
    case title = "AXTitle"
    case description = "AXDescription"
    case identifier = "AXIdentifier"
    case parent = "AXParent"
    case children = "AXChildren"
    case visibleRows = "AXVisibleRows"
    case position = "AXPosition"
    case size = "AXSize"
    case value = "AXValue"
    case url = "AXURL"
    case document = "AXDocument"
    case focusedApplication = "AXFocusedApplication"
    case focusedWindow = "AXFocusedWindow"
    case mainWindow = "AXMainWindow"
    case focusedUIElement = "AXFocusedUIElement"
    case selectedTextRange = "AXSelectedTextRange"
    case visibleCharacterRange = "AXVisibleCharacterRange"
    case numberOfCharacters = "AXNumberOfCharacters"
    case insertionPointLineNumber = "AXInsertionPointLineNumber"
}

enum Role: String {
    case unknown = "AXUnknown"
    case button = "AXButton"
    case radioButton = "AXRadioButton"
    case checkBox = "AXCheckBox"
    case slider = "AXSlider"
    case tabGroup = "AXTabGroup"
    case textField = "AXTextField"
    case staticText = "AXStaticText"
    case textArea = "AXTextArea"
    case webArea = "AXWebArea"
    case scrollArea = "AXScrollArea"
    case popUpButton = "AXPopUpButton"
    case menuButton = "AXMenuButton"
    case table = "AXTable"
    case application = "AXApplication"
    case group = "AXGroup"
    case radioGroup = "AXRadioGroup"
    case list = "AXList"
    case scrollBar = "AXScrollBar"
    case valueIndicator = "AXValueIndicator"
    case image = "AXImage"
    case menuBar = "AXMenuBar"
    case menu = "AXMenu"
    case menuItem = "AXMenuItem"
    case column = "AXColumn"
    case row = "AXRow"
    case toolbar = "AXToolbar"
    case busyIndicator = "AXBusyIndicator"
    case progressIndicator = "AXProgressIndicator"
    case window = "AXWindow"
    case drawer = "AXDrawer"
    case systemWide = "AXSystemWide"
    case outline = "AXOutline"
    case incrementor = "AXIncrementor"
    case browser = "AXBrowser"
    case comboBox = "AXComboBox"
    case splitGroup = "AXSplitGroup"
    case splitter = "AXSplitter"
    case colorWell = "AXColorWell"
    case growArea = "AXGrowArea"
    case sheet = "AXSheet"
    case helpTag = "AXHelpTag"
    case matte = "AXMatte"
    case ruler = "AXRuler"
    case rulerMarker = "AXRulerMarker"
    case link = "AXLink"
    case disclosureTriangle = "AXDisclosureTriangle"
    case grid = "AXGrid"
    case relevanceIndicator = "AXRelevanceIndicator"
    case levelIndicator = "AXLevelIndicator"
    case cell = "AXCell"
    case popover = "AXPopover"
    case layoutArea = "AXLayoutArea"
    case layoutItem = "AXLayoutItem"
    case handle = "AXHandle"
}

enum Subrole: String {
    case standardWindow = "AXStandardWindow"
    case dialog = "AXDialog"
    case systemDialog = "AXSystemDialog"
    case searchField = "AXSearchField"
    case secureTextField = "AXSecureTextField"
}

enum AXNotification: String {
    case mainWindowChanged = "AXMainWindowChanged"
    case focusedWindowChanged = "AXFocusedWindowChanged"
    case focusedUIElementChanged = "AXFocusedUIElementChanged"
    case applicationActivated = "AXApplicationActivated"
    case applicationDeactivated = "AXApplicationDeactivated"
    case applicationHidden = "AXApplicationHidden"
    case applicationShown = "AXApplicationShown"
    case windowCreated = "AXWindowCreated"
    case windowMoved = "AXWindowMoved"
    case windowResized = "AXWindowResized"
    case windowMiniaturized = "AXWindowMiniaturized"
    case windowDeminiaturized = "AXWindowDeminiaturized"
    case drawerCreated = "AXDrawerCreated"
    case sheetCreated = "AXSheetCreated"
    case uiElementDestroyed = "AXUIElementDestroyed"
    case valueChanged = "AXValueChanged"
    case titleChanged = "AXTitleChanged"
    case resized = "AXResized"
    case moved = "AXMoved"
    case created = "AXCreated"
    case layoutChanged = "AXLayoutChanged"
    case helpTagCreated = "AXHelpTagCreated"
    case selectedTextChanged = "AXSelectedTextChanged"
    case rowCountChanged = "AXRowCountChanged"
    case selectedChildrenChanged = "AXSelectedChildrenChanged"
    case selectedRowsChanged = "AXSelectedRowsChanged"
    case selectedColumnsChanged = "AXSelectedColumnsChanged"
    case rowExpanded = "AXRowExpanded"
    case rowCollapsed = "AXRowCollapsed"
    case selectedCellsChanged = "AXSelectedCellsChanged"
    case unitsChanged = "AXUnitsChanged"
    case selectedChildrenMoved = "AXSelectedChildrenMoved"
    case announcementRequested = "AXAnnouncementRequested"
}

// Keep the native error code intact so callers can distinguish missing
// attributes from transient IPC failures when deciding whether to retry.
extension AXError: Swift.Error {}

class UIElement: Hashable {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    static func == (lhs: UIElement, rhs: UIElement) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }

    var messagingTimeout: Float = 0 {
        didSet {
            // AX has no corresponding getter. The stored value is the timeout
            // requested for this object, while zero restores the system default.
            AXUIElementSetMessagingTimeout(element, max(0, messagingTimeout))
        }
    }

    func pid() throws -> pid_t {
        var processID: pid_t = 0
        try Self.check(AXUIElementGetPid(element, &processID))
        return processID
    }

    func role() throws -> Role? {
        let name: String? = try attribute(.role)
        return name.flatMap(Role.init(rawValue:))
    }

    func subrole() throws -> Subrole? {
        let name: String? = try attribute(.subrole)
        return name.flatMap(Subrole.init(rawValue:))
    }

    func attribute<T>(_ name: Attribute) throws -> T? {
        try attribute(name.rawValue)
    }

    func attribute<T>(_ name: String) throws -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result != .noValue, result != .attributeUnsupported else { return nil }
        try Self.check(result)
        guard let value else { return nil }
        return try Self.decode(value, as: T.self)
    }

    func parameterizedAttribute<T>(_ name: String, param: Any) throws -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element, name as CFString, param as AnyObject, &value
        )
        guard result != .noValue,
              result != .attributeUnsupported,
              result != .parameterizedAttributeUnsupported else { return nil }
        try Self.check(result)
        guard let value else { return nil }
        return try Self.decode(value, as: T.self)
    }

    func attributeIsSettable(_ name: String) throws -> Bool {
        var writable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, name as CFString, &writable)
        guard result != .noValue, result != .attributeUnsupported else { return false }
        try Self.check(result)
        return writable.boolValue
    }

    func setAttribute(_ name: String, value: Any) throws {
        let nativeValue: AnyObject
        if let wrapped = value as? UIElement {
            nativeValue = wrapped.element
        } else {
            nativeValue = value as AnyObject
        }
        try Self.check(AXUIElementSetAttributeValue(element, name as CFString, nativeValue))
    }

    func getMultipleAttributes(_ names: [Attribute]) throws -> [Attribute: Any] {
        guard !names.isEmpty else { return [:] }
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(
            element, names.map(\.rawValue) as CFArray, [], &values
        )
        guard result != .noValue, result != .attributeUnsupported else { return [:] }
        try Self.check(result)
        guard let values else { throw AXError.failure }
        let members = values as [AnyObject]
        guard members.count == names.count else { throw AXError.failure }
        var attributes: [Attribute: Any] = [:]
        for (name, value) in zip(names, members) {
            // Missing optional attributes do not discard useful siblings.
            // Preserve transport failures so callers can retry an unready app.
            if CFGetTypeID(value) == AXValueGetTypeID() {
                let boxed = unsafeBitCast(value, to: AXValue.self)
                if AXValueGetType(boxed) == .axError {
                    guard let error = boxed.asError else { throw AXError.failure }
                    if error == .noValue || error == .attributeUnsupported { continue }
                    throw error
                }
            }
            if CFGetTypeID(value) != CFNullGetTypeID() {
                attributes[name] = try Self.decode(value, as: Any.self)
            }
        }
        return attributes
    }

    private static func check(_ result: AXError) throws {
        if result != .success { throw result }
    }

    /// Convert only the system types callers ask for. In particular an array
    /// requested as [AXUIElement] remains native, rather than being wrapped.
    static func decode<T>(_ value: CFTypeRef, as type: T.Type) throws -> T {
        let typeID = CFGetTypeID(value)
        if type == UIElement.self, typeID == AXUIElementGetTypeID() {
            let native = unsafeBitCast(value, to: AXUIElement.self)
            if let result = UIElement(native) as? T { return result }
        }
        if type == [UIElement].self, let native = value as? [AXUIElement],
           let result = native.map(UIElement.init) as? T {
            return result
        }
        if typeID == AXValueGetTypeID() {
            let native = unsafeBitCast(value, to: AXValue.self)
            let decoded: Any?
            switch AXValueGetType(native) {
            case .cgPoint: decoded = native.asPoint
            case .cgSize: decoded = native.asSize
            case .cgRect: decoded = native.asRect
            case .cfRange: decoded = native.asRange
            case .axError:
                if let error = native.asError { throw error }
                throw AXError.failure
            default: decoded = value
            }
            guard let result = decoded as? T else { throw AXError.illegalArgument }
            return result
        }
        guard let result = value as? T else { throw AXError.illegalArgument }
        return result
    }
}

final class Application: UIElement {
    convenience init?(_ application: NSRunningApplication) {
        guard !application.isTerminated, application.processIdentifier > 0 else { return nil }
        self.init(AXUIElementCreateApplication(application.processIdentifier))
    }

    convenience init?(forProcessID processID: pid_t) {
        guard processID > 0, let running = NSRunningApplication(processIdentifier: processID) else { return nil }
        self.init(running)
    }
}

let systemWideElement = UIElement(AXUIElementCreateSystemWide())

/// Delivers native AX notifications on the run loop that created the observer.
/// Keeping that run loop also makes stop/deinit remove the correct source when
/// a cancellation is initiated from a different thread.
final class Observer {
    typealias Callback = (Observer, UIElement, AXNotification) -> Void
    typealias CallbackWithInfo = (Observer, UIElement, AXNotification, [String: AnyObject]?) -> Void

    private let native: AXObserver
    private let callback: CallbackWithInfo
    private let runLoop: CFRunLoop
    private let stateLock = NSLock()
    private var running = false

    convenience init(processID: pid_t, callback: @escaping Callback) throws {
        try self.init(processID: processID) { observer, element, notification, _ in
            callback(observer, element, notification)
        }
    }

    init(processID: pid_t, callback: @escaping CallbackWithInfo) throws {
        guard processID > 0 else { throw AXError.illegalArgument }
        var created: AXObserver?
        let result = AXObserverCreateWithInfoCallback(processID, Self.deliver, &created)
        guard result == .success else { throw result }
        guard let created else { throw AXError.failure }
        native = created
        self.callback = callback
        runLoop = CFRunLoopGetCurrent()
        start()
    }

    deinit { stop() }

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !running else { return }
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(native), .defaultMode)
        running = true
    }

    func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard running else { return }
        CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(native), .defaultMode)
        running = false
    }

    func addNotification(_ name: AXNotification, forElement element: UIElement) throws {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(native, element.element, name.rawValue as CFString, context)
        if result != .success, result != .notificationAlreadyRegistered { throw result }
    }

    func removeNotification(_ name: AXNotification, forElement element: UIElement) throws {
        let result = AXObserverRemoveNotification(native, element.element, name.rawValue as CFString)
        if result != .success, result != .notificationNotRegistered { throw result }
    }

    private static let deliver: AXObserverCallbackWithInfo = { _, nativeElement, name, info, context in
        guard let context, let notification = AXNotification(rawValue: name as String) else { return }
        let observer = Unmanaged<Observer>.fromOpaque(context).takeUnretainedValue()
        let userInfo = info as NSDictionary as? [String: AnyObject]
        observer.callback(observer, UIElement(nativeElement), notification, userInfo)
    }
}
