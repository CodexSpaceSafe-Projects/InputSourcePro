import Cocoa
import Combine

@MainActor
class StatusItemController {
    let navigationVM: NavigationVM
    let permissionsVM: PermissionsVM
    let preferencesVM: PreferencesVM
    let applicationVM: ApplicationVM
    let indicatorVM: IndicatorVM
    let inputSourceVM: InputSourceVM

    let cancelBag = CancelBag()

    var statusItem: NSStatusItem?
    var hasPreferencesShown = false

    var addRuleMenu: NSMenuItem? {
        guard let app = applicationVM.appKind?.getApp() else { return nil }

        var items: [NSMenuItem] = [
            AppRuleMenuItem(app: app, preferencesVM: preferencesVM, inputSourceVM: inputSourceVM, inputSource: nil),
            NSMenuItem.separator(),
        ]

        items[0].toolTip = "Default Keyboard Tooltip".i18n()

        items += InputSource.sources.map {
            AppRuleMenuItem(app: app, preferencesVM: preferencesVM, inputSourceVM: inputSourceVM, inputSource: $0)
        }

        items
            .filter { (($0 as? AppRuleMenuItem) != nil) ? true : false }
            .enumerated()
            .forEach { index, item in
                if index < 10 {
                    item.keyEquivalent = "\(index)"
                    item.keyEquivalentModifierMask = .command
                }
            }

        let menu = NSMenuItem(
            title: String(format: "Default Keyboard for %@".i18n(), app.ruleDisplayName),
            submenuItems: items
        )

        menu.toolTip = app.bundleIdentifier

        return menu
    }

    var addBrowserRuleMenu: NSMenuItem? {
        guard let appKind = applicationVM.appKind,
              let browserInfo = appKind.getBrowserInfo(),
              let browserURL = browserInfo.url,
              let host = browserURL.host
        else { return nil }

        let app = appKind.getApp()

        var items: [NSMenuItem] = [
            BrowserRuleMenuItem(
                app: app,
                url: browserURL,
                preferencesVM: preferencesVM,
                inputSourceVM: inputSourceVM,
                inputSource: nil
            ),
            NSMenuItem.separator(),
        ]

        items[0].toolTip = "Default Keyboard Tooltip".i18n()

        items += InputSource.sources.map {
            BrowserRuleMenuItem(
                app: app,
                url: browserURL,
                preferencesVM: preferencesVM,
                inputSourceVM: inputSourceVM,
                inputSource: $0
            )
        }

        items
            .filter { (($0 as? BrowserRuleMenuItem) != nil) ? true : false }
            .enumerated()
            .forEach { index, item in
                if index < 10 {
                    item.keyEquivalent = "\(index)"
                    item.keyEquivalentModifierMask = .command
                }
            }

        return NSMenuItem(
            title: String(format: "Default Keyboard for %@".i18n(), host),
            submenuItems: items
        )
    }

    var settingsMenu: NSMenuItem? {
        NSMenuItem(
            title: "Preferences".i18n() + "...",
            target: self,
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
    }

    var menu: NSMenu {
        let menu = NSMenu()

        let items = [
            NSMenuItem(title: "Input Source Pro".i18n(), action: nil, keyEquivalent: ""),
            addBrowserRuleMenu ?? addRuleMenu,
            NSMenuItem.separator(),
            settingsMenu,
            NSMenuItem.separator(),
            NSMenuItem(
                title: "Quit".i18n(),
                action: #selector(NSApplication.shared.terminate(_:)),
                keyEquivalent: "q"
            ),
        ]
        .compactMap { $0 }

        items.forEach { menu.addItem($0) }

        return menu
    }

    lazy var preferencesWindowController = PreferencesWindowController(
        navigationVM: self.navigationVM,
        permissionsVM: self.permissionsVM,
        preferencesVM: self.preferencesVM,
        indicatorVM: self.indicatorVM,
        inputSourceVM: self.inputSourceVM
    )

    init(
        navigationVM: NavigationVM,
        permissionsVM: PermissionsVM,
        preferencesVM: PreferencesVM,
        applicationVM: ApplicationVM,
        indicatorVM: IndicatorVM,
        inputSourceVM: InputSourceVM
    ) {
        self.navigationVM = navigationVM
        self.permissionsVM = permissionsVM
        self.preferencesVM = preferencesVM
        self.applicationVM = applicationVM
        self.indicatorVM = indicatorVM
        self.inputSourceVM = inputSourceVM

        preferencesVM.$preferences
            .map(\.isShowIconInMenuBar)
            .removeDuplicates()
            .map { isShow -> AnyPublisher<Void, Never> in
                if isShow {
                    return AnyPublisher.create { [unowned self] _ in
                        statusItem = NSStatusBar.system.statusItem(
                            withLength: NSStatusItem.squareLength
                        )

                        statusItem?.button?.image = NSImage(named: "MenuBarIcon")
                        statusItem?.button?.image?.size = NSSize(width: 16, height: 16)
                        statusItem?.button?.image?.isTemplate = true
                        statusItem?.button?.target = self
                        statusItem?.button?.action = #selector(self.displayMenu)

                        return AnyCancellable { [unowned self] in
                            self.statusItem = nil
                        }
                    }
                } else {
                    return Empty<Void, Never>().eraseToAnyPublisher()
                }
            }
            .switchToLatest()
            .sink {}
            .store(in: cancelBag)
    }

    @objc func displayMenu() {
        // https://stackoverflow.com/a/57612963
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func openPreferences() {
        NSApp.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = preferencesWindowController.window {
            DispatchQueue.main.async {
                if !self.hasPreferencesShown {
                    self.hasPreferencesShown = true
                    // Resolve SwiftUI's initial window size before centering it.
                    window.updateConstraintsIfNeeded()
                    window.layoutIfNeeded()
                    window.center()
                }
                
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
