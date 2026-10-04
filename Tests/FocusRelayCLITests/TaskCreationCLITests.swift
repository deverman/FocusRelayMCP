import Foundation
import Testing
@testable import FocusRelayCLI
import OmniFocusCore

@Suite("Task creation CLI contract")
struct TaskCreationCLITests {
    @Test func sparseJSONUsesSafeDefaultsAndSameTypedContract() throws {
        let json = #"{"creationKey":"00000000-0000-0000-0000-000000000001","tasks":[{"clientID":"one","name":"Synthetic"}]}"#
        let command = try AddTasks.parse(["--request-json", json])
        let request = try command.makeRequest()
        #expect(request.previewOnly)
        #expect(request.destination.kind == .inbox)
        #expect(request == (try JSONDecoder().decode(TaskCreationRequest.self, from: Data(json.utf8))))
    }

    @Test(arguments: [
        #"{"creationKey":"00000000-0000-0000-0000-000000000001","previewOnly":false,"tasks":[{"clientID":"one","name":"Synthetic"}]}"#,
        #"{"creationKey":"00000000-0000-0000-0000-000000000001","tasks":[{"clientID":"one","name":"Synthetic","notes":"Typo"}]}"#,
        #"{"creationKey":"00000000-0000-0000-0000-000000000001","tasks":[{"clientID":"one","name":"Synthetic","due":{"on":"2026-02-30","time":{"policy":"omnifocus_default"}}}]}"#
    ])
    func invalidOrUnknownFieldsFailBeforeService(json: String) throws {
        let command = try AddTasks.parse(["--request-json", json])
        #expect(throws: (any Error).self) { try command.makeRequest() }
    }

    @Test func inputSourcesAreMutuallyExclusive() throws {
        #expect(throws: (any Error).self) { try AddTasks.parse([]).makeRequest() }
        #expect(throws: (any Error).self) { try AddTasks.parse(["--request-json", "{}", "--request-file", "/tmp/unused"]).makeRequest() }
    }
}
