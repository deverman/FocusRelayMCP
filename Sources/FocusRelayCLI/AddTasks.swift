import ArgumentParser
import Foundation
import FocusRelayServer
import OmniFocusAutomation
import OmniFocusCore

struct AddTasks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add-tasks",
        abstract: "Preview or apply approved task creation using the same JSON contract as MCP add_tasks.", aliases: ["add_tasks"])

    @Option(name: .customLong("request-json"), help: "Complete creation request JSON. Preview is the default; apply requires the returned approval ID.")
    var requestJSON: String?

    @Option(name: .customLong("request-file"), help: "Read complete creation request JSON from a UTF-8 file instead of a shell argument.")
    var requestFile: String?

    func makeRequest() throws -> TaskCreationRequest {
        guard (requestJSON != nil) != (requestFile != nil) else {
            throw ValidationError("Provide exactly one of --request-json or --request-file.")
        }
        let data: Data
        if let requestJSON { data = Data(requestJSON.utf8) }
        else { data = try Data(contentsOf: URL(fileURLWithPath: requestFile!)) }
        let request = try JSONDecoder().decode(TaskCreationRequest.self, from: data)
        try request.validate()
        try FocusRelayServer.validateCreationJSON(data)
        return request
    }

    func run() async throws {
        let result = try await OmniFocusBridgeService().addTasks(makeRequest())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(result), as: UTF8.self))
        if result.status == .partial || result.status == .uncertain { throw ExitCode.failure }
    }
}
