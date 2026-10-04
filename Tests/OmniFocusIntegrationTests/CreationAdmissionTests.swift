import Darwin
import Foundation
import Testing
@testable import OmniFocusAutomation
import OmniFocusCore

@Suite("Durable creation admission")
struct CreationAdmissionTests {
    @Test func realBridgeWireCarriesBoundIntentAndSurvivesClientUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = IPCPaths(baseURL: directory.appendingPathComponent("FocusRelayIPC"))
        let key = UUID().uuidString
        let request = TaskCreationRequest(creationKey: key, tasks: [.init(clientID: "fixture", name: "Synthetic wire fixture")])
        let fingerprint = try request.intentFingerprint()
        let receipt = paths.creationStateURL.appendingPathComponent(key + ".json")
        var dispatches = 0
        for _ in 0..<2 {
            // A fresh client runs the real startup/version maintenance path.
            let client = BridgeClient(paths: paths)
            client.dispatchHandlerForTesting = { requestID in
                dispatches += 1
                let data = try Data(contentsOf: paths.requestsURL.appendingPathComponent(requestID + ".json"))
                let wire = try JSONDecoder().decode(BridgeRequest.self, from: data)
                #expect(wire.op == "add_tasks")
                #expect(wire.creation == request)
                #expect(wire.creationFingerprint == fingerprint)
                #expect(wire.userTimeZone == TimeZone.current.identifier)
                let previewID = try #require(wire.creationPreviewID)
                #expect(UUID(uuidString: previewID) != nil)
                if dispatches == 2 { #expect(FileManager.default.fileExists(atPath: receipt.path)) }
                try Data("{}".utf8).write(to: receipt)
                let response = #"{"schemaVersion":1,"requestId":"\#(requestID)","ok":true,"data":{"status":"previewed","creationKey":"\#(key)","previewID":"\#(previewID)","destination":{"kind":"inbox"},"results":[],"message":"Synthetic preview"}}"#
                try Data(response.utf8).write(to: paths.responsesURL.appendingPathComponent(requestID + ".json"))
            }
            #expect(try client.addTasks(request).status == .previewed)
            client.recordObservedPluginVersion(UUID().uuidString)
        }
        #expect(dispatches == 2)
        try FileManager.default.removeItem(at: receipt)
        let retry = BridgeClient(paths: paths)
        retry.dispatchHandlerForTesting = { _ in Issue.record("Lost receipt must reject before dispatch") }
        #expect(throws: MutationValidationError.self) { _ = try retry.addTasks(request) }
        #expect(FileManager.default.fileExists(atPath: paths.creationStateURL.appendingPathComponent(key + ".admission").path))
    }

    @Test func sameKeyCannotAcquireASecondLockAndTombstoneSurvives() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = directory.appendingPathComponent("state/creation-v1")
        let key = UUID().uuidString
        try CreationAdmission.withLock(directory: state, key: key) { firstUse in
            #expect(firstUse)
            #expect(throws: MutationValidationError.self) {
                try CreationAdmission.withLock(directory: state, key: key) { _ in Issue.record("Duplicate admission") }
            }
        }
        try CreationAdmission.withLock(directory: state, key: key) { firstUse in #expect(!firstUse) }
        let attributes = try FileManager.default.attributesOfItem(atPath: state.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let lock = try FileManager.default.attributesOfItem(atPath: state.appendingPathComponent(key + ".admission").path)
        #expect((lock[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func stateIsSeparateFromDisposableIPCAndSymlinksFail() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = IPCPaths(baseURL: directory.appendingPathComponent("FocusRelayIPC"))
        #expect(!paths.creationStateURL.path.hasPrefix(paths.baseURL.path + "/"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("FocusRelayState"), withDestinationURL: directory)
        #expect(throws: MutationValidationError.self) {
            try CreationAdmission.withLock(directory: paths.creationStateURL, key: UUID().uuidString) { _ in Issue.record("Symlink admission") }
        }
    }
}
