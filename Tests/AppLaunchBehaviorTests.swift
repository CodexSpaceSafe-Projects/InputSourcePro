import AppKit
import XCTest
@testable import Input_Source_Pro

@MainActor
final class AppLaunchBehaviorTests: XCTestCase {
    func testFirstLaunchOpensPreferences() {
        let delegate = RecordingAppDelegate()
        delegate.openPreferencesAtFirstLaunch(previousBuildVersion: 0, currentBuildVersion: 707)
        XCTAssertEqual(delegate.preferencesOpenCount, 1)
    }

    func testLaunchingSameVersionDoesNotOpenPreferences() {
        let delegate = RecordingAppDelegate()
        delegate.openPreferencesAtFirstLaunch(previousBuildVersion: 707, currentBuildVersion: 707)
        XCTAssertEqual(delegate.preferencesOpenCount, 0)
    }

    func testLaunchingDifferentVersionOpensPreferences() {
        for previousBuildVersion in [706, 708] {
            let delegate = RecordingAppDelegate()
            delegate.openPreferencesAtFirstLaunch(previousBuildVersion: previousBuildVersion, currentBuildVersion: 707)
            XCTAssertEqual(delegate.preferencesOpenCount, 1)
        }
    }

    func testOrdinaryActivationOpensPreferences() {
        let delegate = RecordingAppDelegate()
        delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        XCTAssertEqual(delegate.preferencesOpenCount, 1)
    }

    func testExplicitReopenOpensPreferences() {
        for hasVisibleWindows in [false, true] {
            let delegate = RecordingAppDelegate()
            XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: hasVisibleWindows))
            XCTAssertEqual(delegate.preferencesOpenCount, 1)
        }
    }
}

@MainActor
private final class RecordingAppDelegate: AppDelegate {
    private(set) var preferencesOpenCount = 0

    override func openPreferences() {
        preferencesOpenCount += 1
    }
}
