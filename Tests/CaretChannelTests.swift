import XCTest
import Darwin
@testable import Input_Source_Pro

final class CaretChannelTests: XCTestCase {
    private let activity = CaretActivity(pid: 42, uptime: 10, focusID: "field", permitsTracking: true, isInputEvent: true)

    func testFramesSurvivePartialAndCombinedSocketReads() throws {
        let first = CaretMessage.activity(activity)
        let second = CaretMessage.position(CaretPosition(session: "session", pid: 42, uptime: 10,
                                                       rect: "{{20, 30}, {1, 16}}", pending: false, focusID: "field"))
        let bytes = try CaretChannel.Decoder.frame(first) + CaretChannel.Decoder.frame(second)
        var decoder = CaretChannel.Decoder()
        XCTAssertTrue(try decoder.append(bytes.prefix(2)).isEmpty)
        XCTAssertTrue(try decoder.append(bytes.subdata(in: 2..<7)).isEmpty)
        XCTAssertEqual(try decoder.append(bytes.subdata(in: 7..<bytes.count)), [first, second])
    }

    func testMalformedAndOversizedMessagesAreRejected() throws {
        for bytes in [Data([0, 0, 0, 0]), Data([0, 0, 16, 1]), Data([0, 0, 0, 1, 255])] {
            var decoder = CaretChannel.Decoder()
            XCTAssertThrowsError(try decoder.append(bytes))
        }
        let large = CaretActivity(pid: 42, uptime: 10, focusID: String(repeating: "x", count: 5000),
                                  permitsTracking: true, isInputEvent: false)
        XCTAssertThrowsError(try CaretChannel.Decoder.frame(.activity(large)))
    }

    func testPeersCannotInvokeMessagesInTheWrongDirection() {
        XCTAssertTrue(CaretChannel.Role.application.accepts(.ready))
        XCTAssertFalse(CaretChannel.Role.helper.accepts(.ready))
        XCTAssertTrue(CaretChannel.Role.helper.accepts(.activity(activity)))
        XCTAssertFalse(CaretChannel.Role.application.accepts(.activity(activity)))
        let position = CaretMessage.position(CaretPosition(session: "s", pid: 42, uptime: 10, rect: "", pending: false, focusID: ""))
        XCTAssertTrue(CaretChannel.Role.application.accepts(position))
        XCTAssertFalse(CaretChannel.Role.helper.accepts(position))
    }

    func testTrackingRequiresFreshAuthorizationAndStopsForSecureInput() {
        XCTAssertTrue(activity.permitsQuery(pid: 42, now: 10.2, secureInput: false))
        XCTAssertFalse(activity.permitsQuery(pid: 42, now: 10.2, secureInput: true))
        XCTAssertFalse(activity.permitsQuery(pid: 43, now: 10.2, secureInput: false))
        XCTAssertFalse(activity.permitsQuery(pid: 42, now: 11, secureInput: false))
        XCTAssertFalse(activity.permitsQuery(pid: 42, now: 9, secureInput: false))
        let denied = CaretActivity(pid: 42, uptime: 10, focusID: "field", permitsTracking: false, isInputEvent: true)
        XCTAssertFalse(denied.permitsQuery(pid: 42, now: 10.2, secureInput: false))
    }

    func testSecureTextFieldsDoNotPermitCursorTracking() {
        XCTAssertFalse(CaretPalette.TextFocus(role: .textField, subrole: "AXSecureTextField").permitsCaret)
        XCTAssertTrue(CaretPalette.TextFocus(role: .textField, subrole: nil).permitsCaret)
    }

    private func ownExecutableURL() throws -> URL {
        try CaretChannel.ProcessIdentity.current().executable
    }

    private func socketURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ipc-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("s")
    }

    func testAuthenticatedPeersExchangeMessagesAndDisconnect() async throws {
        let url = try socketURL()
        let executable = try ownExecutableURL()
        let received = expectation(description: "private activity received")
        let disconnected = expectation(description: "helper stops when owner disconnects")
        let ready = expectation(description: "authenticated helper acknowledges connection")
        let app = try CaretChannel(role: .application, socketURL: url, peerExecutableURL: executable,
                                   onMessage: { message in
            XCTAssertEqual(message, .ready)
            ready.fulfill()
        }, onConnectionChange: { _ in })
        let helper = try CaretChannel(role: .helper, socketURL: url, peerExecutableURL: executable,
                                     onMessage: { [activity] message in
            XCTAssertEqual(message, .activity(activity))
            received.fulfill()
        }, onConnectionChange: { [activity] connected in
            if connected { app.send(.activity(activity)) }
            else { disconnected.fulfill() }
        })
        defer { helper.stop(); app.stop() }
        try app.start()
        try helper.start()
        await fulfillment(of: [received], timeout: 5)
        helper.send(.ready)
        await fulfillment(of: [ready], timeout: 5)
        app.stop()
        await fulfillment(of: [disconnected], timeout: 5)
    }

    func testUntrustedClientCannotReceivePrivateActivity() async throws {
        let url = try socketURL()
        let rejected = expectation(description: "untrusted client never accepted")
        rejected.isInverted = true
        let app = try CaretChannel(role: .application, socketURL: url,
                                  peerExecutableURL: URL(fileURLWithPath: "/not-the-installed-helper/CaretControl"),
                                  onMessage: { _ in rejected.fulfill() },
                                  onConnectionChange: { if $0 { rejected.fulfill() } })
        let helper = try CaretChannel(role: .helper, socketURL: url,
                                     onMessage: { _ in rejected.fulfill() }, onConnectionChange: { _ in })
        defer { helper.stop(); app.stop() }
        try app.start()
        try helper.start()
        app.send(.activity(activity))
        await fulfillment(of: [rejected], timeout: 1.5)
    }

    func testPeerAuthenticationDoesNotRequireASharedSigningIdentity() async throws {
        let url = try socketURL()
        let connected = expectation(description: "separate native process connects")
        let received = expectation(description: "separate native process receives activity")
        let output = Pipe()
        var decoder = CaretChannel.Decoder()
        let message = CaretMessage.activity(activity)
        output.fileHandleForReading.readabilityHandler = { file in
            let bytes = file.availableData
            guard !bytes.isEmpty else { return }
            do {
                for decoded in try decoder.append(bytes) {
                    XCTAssertEqual(decoded, message)
                    received.fulfill()
                }
            } catch { XCTFail("Invalid frame: \(error)") }
        }
        // macOS supplies nc with a different signing identity and no app/helper bundle identifier.
        let executable = URL(fileURLWithPath: "/usr/bin/nc")
        let app = try CaretChannel(role: .application, socketURL: url, peerExecutableURL: executable,
                                   onMessage: { _ in }, onConnectionChange: { isConnected in
            if isConnected { connected.fulfill() }
        })
        let client = Process()
        client.executableURL = executable
        client.arguments = ["-U", url.path]
        client.standardInput = Pipe()
        client.standardOutput = output
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            if client.isRunning { client.terminate() }
            app.stop()
        }
        try app.start()
        try client.run()
        await fulfillment(of: [connected], timeout: 5)
        app.send(message)
        await fulfillment(of: [received], timeout: 5)
    }

    func testHelperRejectsAnImpersonatedApp() async throws {
        let url = try socketURL()
        let rejected = expectation(description: "fake application never accepted")
        rejected.isInverted = true
        let app = try CaretChannel(role: .application, socketURL: url, peerExecutableURL: try ownExecutableURL(),
                                  onMessage: { _ in rejected.fulfill() }, onConnectionChange: { _ in })
        let helper = try CaretChannel(role: .helper, socketURL: url,
                                     peerExecutableURL: URL(fileURLWithPath: "/not-the-listening-app/Input Source Pro"),
                                     onMessage: { _ in rejected.fulfill() },
                                     onConnectionChange: { if $0 { rejected.fulfill() } })
        defer { helper.stop(); app.stop() }
        try app.start()
        try helper.start()
        await fulfillment(of: [rejected], timeout: 1.5)
    }

    func testAnotherListenerCannotReplaceTheOwnersSocket() throws {
        let url = try socketURL()
        let first = try CaretChannel(role: .application, socketURL: url, onMessage: { _ in }, onConnectionChange: { _ in })
        let second = try CaretChannel(role: .application, socketURL: url, onMessage: { _ in }, onConnectionChange: { _ in })
        defer { first.stop(); second.stop() }
        try first.start()
        let owner = try Data(contentsOf: url.appendingPathExtension("owner"))
        XCTAssertThrowsError(try second.start())
        second.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("owner")), owner)
    }

    func testSocketDirectorySymlinkIsRejected() throws {
        let url = try socketURL()
        let link = url.deletingLastPathComponent().appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url.deletingLastPathComponent())
        let app = try CaretChannel(role: .application, socketURL: link.appendingPathComponent("s"),
                                  onMessage: { _ in }, onConnectionChange: { _ in })
        XCTAssertThrowsError(try app.start())
    }

    func testDefaultChannelRejectsAnExecutableOutsideTheInstalledHelper() async throws {
        let url = try socketURL()
        let rejected = expectation(description: "only the installed helper may connect")
        rejected.isInverted = true
        let app = try CaretChannel(role: .application, socketURL: url, onMessage: { _ in rejected.fulfill() },
                                   onConnectionChange: { if $0 { rejected.fulfill() } })
        let helper = try CaretChannel(role: .helper, socketURL: url,
                                     onMessage: { _ in rejected.fulfill() }, onConnectionChange: { _ in })
        defer { helper.stop(); app.stop() }
        try app.start()
        try helper.start()
        await fulfillment(of: [rejected], timeout: 1.5)
    }

    private func assertOwnerRejected(change: (URL) throws -> Void) async throws {
        let url = try socketURL()
        let rejected = expectation(description: "helper rejects invalid listener identity")
        rejected.isInverted = true
        let app = try CaretChannel(role: .application, socketURL: url, peerExecutableURL: try ownExecutableURL(),
                                   onMessage: { _ in }, onConnectionChange: { _ in })
        let helper = try CaretChannel(role: .helper, socketURL: url,
                                     onMessage: { _ in rejected.fulfill() },
                                     onConnectionChange: { if $0 { rejected.fulfill() } })
        defer { helper.stop(); app.stop() }
        try app.start()
        try change(url.appendingPathExtension("owner"))
        try helper.start()
        await fulfillment(of: [rejected], timeout: 1.5)
    }

    func testHelperRejectsAReusedPIDWithADifferentAuditToken() async throws {
        try await assertOwnerRejected { url in
            let own = try CaretChannel.ProcessIdentity.current()
            let stale = CaretChannel.ProcessIdentity(pid: own.pid, executable: own.executable,
                                                     auditToken: Data(repeating: 0, count: own.auditToken.count))
            try JSONEncoder().encode(stale).write(to: url)
        }
    }

    func testHelperRejectsAMismatchedOwnerExecutable() async throws {
        try await assertOwnerRejected { url in
            let own = try CaretChannel.ProcessIdentity.current()
            let fake = CaretChannel.ProcessIdentity(pid: own.pid, executable: URL(fileURLWithPath: "/impostor"),
                                                    auditToken: own.auditToken)
            try JSONEncoder().encode(fake).write(to: url)
        }
    }

    func testHelperRejectsAMismatchedOwnerPID() async throws {
        try await assertOwnerRejected { url in
            let own = try CaretChannel.ProcessIdentity.current()
            let fake = CaretChannel.ProcessIdentity(pid: own.pid + 1, executable: own.executable,
                                                    auditToken: own.auditToken)
            try JSONEncoder().encode(fake).write(to: url)
        }
    }

    func testHelperRejectsAMissingOrMalformedOwnerRecord() async throws {
        try await assertOwnerRejected { try FileManager.default.removeItem(at: $0) }
        try await assertOwnerRejected { try Data("invalid".utf8).write(to: $0) }
        try await assertOwnerRejected { try Data(repeating: 0, count: 4097).write(to: $0) }
    }

    func testHelperRejectsAPublicOwnerRecordOrDirectory() async throws {
        try await assertOwnerRejected { url in
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        try await assertOwnerRejected { url in
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                 ofItemAtPath: url.deletingLastPathComponent().path)
        }
    }

    func testHelperRejectsAnOwnerRecordSymlink() async throws {
        try await assertOwnerRejected { url in
            let target = url.appendingPathExtension("copy")
            try FileManager.default.moveItem(at: url, to: target)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        }
    }

    func testHelperRejectsAnOwnerRecordHardLink() async throws {
        try await assertOwnerRejected { url in
            try FileManager.default.linkItem(at: url, to: url.appendingPathExtension("copy"))
        }
    }

    func testStoppingTheOwnerRemovesItsPrivateSessionRecord() throws {
        let url = try socketURL()
        let app = try CaretChannel(role: .application, socketURL: url, onMessage: { _ in }, onConnectionChange: { _ in })
        try app.start()
        let owner = url.appendingPathExtension("owner")
        let identity = try JSONDecoder().decode(CaretChannel.ProcessIdentity.self, from: Data(contentsOf: owner))
        XCTAssertEqual(identity, try CaretChannel.ProcessIdentity.current())
        let permissions = try FileManager.default.attributesOfItem(atPath: owner.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        app.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: owner.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
