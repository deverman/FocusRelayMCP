import Foundation
import Testing
import OmniFocusCore
@testable import OmniFocusAutomation

@Suite("Task creation single-dispatch boundary")
struct TaskCreationDispatchTests {
    @Test(arguments: ["absent", "locked", "malformed"])
    func uncertainApplyDispatchesOnlyOnce(mode: String) throws {
        let fixture = try DispatchFixture()
        defer { fixture.cleanUp() }
        var dispatches = 0
        fixture.client.dispatchHandlerForTesting = { id in
            dispatches += 1
            if mode == "locked" {
                try Data().write(to: fixture.paths.locksURL.appendingPathComponent(id + ".lock"))
            }
            if mode == "malformed" {
                try Data("not JSON".utf8).write(to: fixture.paths.responsesURL.appendingPathComponent(id + ".json"))
            }
        }
        let response = try fixture.client.addTasks(.init(tasks: [.init(clientID: "one", name: "Synthetic")]))
        #expect(dispatches == 1)
        #expect(response.status == .uncertain)
        #expect(response.results.isEmpty)
        #expect(response.message.contains("Do not automatically repeat"))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("FocusRelayState").path))
    }

    @Test func originalResponseCanArriveLaterWithoutAnotherDispatch() throws {
        let fixture = try DispatchFixture()
        defer { fixture.cleanUp() }
        var dispatches = 0
        fixture.client.dispatchHandlerForTesting = { id in
            dispatches += 1
            let responseURL = fixture.paths.responsesURL.appendingPathComponent(id + ".json")
            let data = Data("""
            {"schemaVersion":1,"requestId":"\(id)","ok":true,"data":{"status":"completed","destination":{"kind":"inbox"},"results":[],"message":"Synthetic success"}}
            """.utf8)
            // Beyond the normal 0.5s stranded-redispatch threshold, but within this deadline.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                try? data.write(to: responseURL, options: .atomic)
            }
        }
        let response = try fixture.client.addTasks(.init(tasks: [.init(clientID: "one", name: "Synthetic")]))
        #expect(response.status == .completed)
        #expect(dispatches == 1)
    }

    @Test func dateOnlyApplyFailsBeforeDispatch() throws {
        let fixture = try DispatchFixture()
        defer { fixture.cleanUp() }
        var dispatches = 0
        fixture.client.dispatchHandlerForTesting = { _ in dispatches += 1 }
        #expect(throws: MutationValidationError.self) {
            try fixture.client.addTasks(.init(tasks: [.init(clientID: "one", name: "Synthetic",
                due: .init(on: "2026-10-06", time: .init()))]))
        }
        #expect(dispatches == 0)
    }

    @Test func queryStillRecoversAStrandedRequest() throws {
        let fixture = try DispatchFixture()
        defer { fixture.cleanUp() }
        var dispatches = 0
        fixture.client.dispatchHandlerForTesting = { id in
            dispatches += 1
            guard dispatches == 2 else { return }
            let data = Data("""
            {"schemaVersion":1,"requestId":"\(id)","ok":true,"data":{"ok":true,"plugin":"Synthetic","version":"test"}}
            """.utf8)
            try data.write(to: fixture.paths.responsesURL.appendingPathComponent(id + ".json"), options: .atomic)
        }
        #expect(try fixture.client.ping().ok)
        #expect(dispatches == 2)
    }
}

private struct DispatchFixture {
    let root: URL
    let paths: IPCPaths
    let client: BridgeClient

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("focusrelay-creation-dispatch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = IPCPaths(baseURL: root.appendingPathComponent("FocusRelayIPC"))
        client = BridgeClient(paths: paths, configuration: .init(responseTimeout: 0.7, responsePollInterval: 0.01))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}
