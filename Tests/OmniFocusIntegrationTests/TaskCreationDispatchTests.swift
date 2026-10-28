import Foundation
import Testing
import OmniFocusCore
@testable import OmniFocusAutomation

@Suite("Task creation single-dispatch boundary")
struct TaskCreationDispatchTests {
    @Test(arguments: ["absent", "locked", "malformed"])
    func uncertainApplyDispatchesOnlyOnce(mode: String) async throws {
        let fixture = try DispatchFixture()
        defer { fixture.cleanUp() }
        fixture.client.dispatchHandlerForTesting = { id in
            fixture.dispatches += 1
            if mode == "locked" {
                try Data().write(to: fixture.paths.locksURL.appendingPathComponent(id + ".lock"))
            }
            if mode == "malformed" {
                try Data("not JSON".utf8).write(to: fixture.paths.responsesURL.appendingPathComponent(id + ".json"))
            }
        }
        let response = try await fixture.perform { client in
            try client.addTasks(.init(tasks: [.init(clientID: "one", name: "Synthetic")]))
        }
        #expect(fixture.dispatches == 1)
        #expect(response.status == .uncertain)
        #expect(response.results.isEmpty)
        #expect(response.message.contains("Do not automatically repeat"))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("FocusRelayState").path))
    }

    @Test func originalResponseCanArriveLaterWithoutAnotherDispatch() async throws {
        let fixture = try DispatchFixture(timeout: 5)
        defer { fixture.cleanUp() }
        fixture.client.dispatchHandlerForTesting = { id in
            fixture.dispatches += 1
            let responseURL = fixture.paths.responsesURL.appendingPathComponent(id + ".json")
            let data = Data("""
            {"schemaVersion":1,"requestId":"\(id)","ok":true,"data":{"status":"completed","destination":{"kind":"inbox"},"results":[],"message":"Synthetic success"}}
            """.utf8)
            // Beyond the normal 0.5s stranded-redispatch threshold, but within this deadline.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                try? data.write(to: responseURL, options: .atomic)
            }
        }
        let response = try await fixture.perform { client in
            try client.addTasks(.init(tasks: [.init(clientID: "one", name: "Synthetic")]))
        }
        #expect(response.status == .completed)
        #expect(fixture.dispatches == 1)
    }

    @Test func dateOnlyApplyFailsBeforeDispatch() throws {
        let fixture = try DispatchFixture()
        defer { fixture.cleanUp() }
        fixture.client.dispatchHandlerForTesting = { _ in fixture.dispatches += 1 }
        #expect(throws: MutationValidationError.self) {
            try fixture.client.addTasks(.init(tasks: [.init(clientID: "one", name: "Synthetic",
                due: .init(on: "2026-10-06", time: .init()))]))
        }
        #expect(fixture.dispatches == 0)
    }

    @Test func queryStillRecoversAStrandedRequest() async throws {
        let fixture = try DispatchFixture()
        defer { fixture.cleanUp() }
        fixture.client.dispatchHandlerForTesting = { id in
            fixture.dispatches += 1
            guard fixture.dispatches == 2 else { return }
            let data = Data("""
            {"schemaVersion":1,"requestId":"\(id)","ok":true,"data":{"ok":true,"plugin":"Synthetic","version":"test"}}
            """.utf8)
            try data.write(to: fixture.paths.responsesURL.appendingPathComponent(id + ".json"), options: .atomic)
        }
        #expect(try await fixture.perform { try $0.ping().ok })
        #expect(fixture.dispatches == 2)
    }
}

// Each fixture is used by one test. Dispatch count is written by its serial worker
// and read only after the awaited operation completes.
private final class DispatchFixture: @unchecked Sendable {
    let root: URL
    let paths: IPCPaths
    let client: BridgeClient

    var dispatches = 0
    private let worker = DispatchQueue(label: "focusrelay.creation-dispatch-test." + UUID().uuidString)

    init(timeout: TimeInterval = 0.7) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("focusrelay-creation-dispatch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = IPCPaths(baseURL: root.appendingPathComponent("FocusRelayIPC"))
        client = BridgeClient(paths: paths, configuration: .init(responseTimeout: timeout, responsePollInterval: 0.01))
    }

    // BridgeClient deliberately blocks while polling. Keep those waits off Swift's
    // cooperative executor so parallel async coordinator tests can make progress.
    func perform<Result: Sendable>(_ work: @escaping @Sendable (BridgeClient) throws -> Result) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            worker.async {
                do { continuation.resume(returning: try work(self.client)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}
