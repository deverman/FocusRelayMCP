import Foundation
import Testing
@testable import FocusRelayCLI
import OmniFocusCore

@Suite("Task creation CLI contract")
struct TaskCreationCLITests {
    @Test func sparseJSONUsesEditDefaultsAndSameTypedContract() throws {
        let json = #"{"tasks":[{"clientID":"one","name":"Synthetic"}]}"#
        let command = try AddTasks.parse(["--request-json", json])
        let request = try command.makeRequest()
        #expect(!request.previewOnly)
        #expect(request.destination.kind == .inbox)
        #expect(request == (try JSONDecoder().decode(TaskCreationRequest.self, from: Data(json.utf8))))
    }

    @Test(arguments: [
        #"{"approvedPreviewID":"removed","tasks":[{"clientID":"one","name":"Synthetic"}]}"#,
        #"{"tasks":[{"clientID":"one","name":"Synthetic","notes":"Typo"}]}"#,
        #"{"tasks":[{"clientID":"one","name":"Synthetic","due":{"on":"2026-02-30","time":{"policy":"omnifocus_default"}}}]}"#
    ])
    func invalidOrUnknownFieldsFailBeforeService(json: String) throws {
        let command = try AddTasks.parse(["--request-json", json])
        #expect(throws: (any Error).self) { try command.makeRequest() }
    }

    @Test func inputSourcesAreMutuallyExclusive() throws {
        #expect(throws: (any Error).self) { try AddTasks.parse([]).makeRequest() }
        #expect(throws: (any Error).self) { try AddTasks.parse(["--request-json", "{}", "--request-file", "/tmp/unused"]).makeRequest() }
    }

    @Test func fileAndInlineInputUseTheSamePreviewContract() throws {
        let json = #"{"previewOnly":true,"tasks":[{"clientID":"parent","name":"Synthetic","children":[{"clientID":"child","name":"Child","due":{"on":"2026-10-06","time":{"policy":"omnifocus_default"}}}]}]}"#
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("focusrelay-creation-input-" + UUID().uuidString + ".json")
        try Data(json.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let inline = try AddTasks.parse(["--request-json", json]).makeRequest()
        let fromFile = try AddTasks.parse(["--request-file", file.path]).makeRequest()
        #expect(inline == fromFile)
        #expect(fromFile.previewOnly)
        #expect(fromFile.tasks[0].children[0].due?.on == "2026-10-06")
    }
}
