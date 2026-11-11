import Cocoa
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var navigationVM: NavigationVM!
    var indicatorVM: IndicatorVM!
    var preferencesVM: PreferencesVM!
    var permissionsVM: PermissionsVM!
    var applicationVM: ApplicationVM!
    var inputSourceVM: InputSourceVM!
    var indicatorWindowController: IndicatorWindowController!
    var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        // Global AX timeout (system default is seconds-long): a hung frontmost app must not freeze every synchronous AX read on the main thread.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)

        navigationVM = NavigationVM()
        permissionsVM = PermissionsVM()
        NativeLaunchAtLogin.disableLegacyHelper()
        preferencesVM = PreferencesVM(permissionsVM: permissionsVM)
        CaretHelperManager.shared.configure(preferences: preferencesVM, permissions: permissionsVM)
        applicationVM = ApplicationVM(preferencesVM: preferencesVM)
        inputSourceVM = InputSourceVM(preferencesVM: preferencesVM)
        indicatorVM = IndicatorVM(permissionsVM: permissionsVM, preferencesVM: preferencesVM, applicationVM: applicationVM, inputSourceVM: inputSourceVM)

        indicatorWindowController = IndicatorWindowController(
            permissionsVM: permissionsVM,
            preferencesVM: preferencesVM,
            indicatorVM: indicatorVM,
            applicationVM: applicationVM,
            inputSourceVM: inputSourceVM
        )

        statusItemController = StatusItemController(
            navigationVM: navigationVM,
            permissionsVM: permissionsVM,
            preferencesVM: preferencesVM,
            applicationVM: applicationVM,
            indicatorVM: indicatorVM,
            inputSourceVM: inputSourceVM
        )
        
        openPreferencesAtFirstLaunch(
            previousBuildVersion: preferencesVM.preferences.prevInstalledBuildVersion,
            currentBuildVersion: preferencesVM.preferences.buildVersion
        )
        updateInstallVersionInfo()

    }

    func applicationDidBecomeActive(_: Notification) {
        guard !InputSourceSwitcher.isHandlingTemporaryInputWindowActivation else { return }
        openPreferences()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        openPreferences()
        return false
    }

    @MainActor
    func openPreferencesAtFirstLaunch(previousBuildVersion: Int, currentBuildVersion: Int) {
        if previousBuildVersion != currentBuildVersion {
            openPreferences()
        }
    }

    @MainActor
    func openPreferences() {
        statusItemController?.openPreferences()
    }

    @MainActor
    func updateInstallVersionInfo() {
        preferencesVM.preferences.prevInstalledBuildVersion = preferencesVM.preferences.buildVersion
    }
}
