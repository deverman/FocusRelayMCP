import ArgumentParser
import FocusRelayOutput
import FocusRelayServer

struct Workflow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workflow",
        abstract: "List or retrieve the same workflow instructions exposed as MCP prompts.",
        subcommands: [WorkflowList.self, WorkflowGet.self]
    )
}

struct WorkflowList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available workflow names and descriptions."
    )

    private struct Summary: Encodable {
        let name: String
        let title: String
        let description: String
    }

    func renderedOutput() throws -> String {
        try encodeJSON(FocusRelayServer.workflows.map {
            Summary(name: $0.name, title: $0.title, description: $0.description)
        })
    }

    func run() throws {
        print(try renderedOutput())
    }
}

struct WorkflowGet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Print one workflow's instruction text."
    )

    @Argument(help: "Exact workflow name from `focusrelay workflow list`.")
    var name: String

    func resolveWorkflow() throws -> FocusRelayWorkflowDefinition {
        guard let workflow = FocusRelayServer.workflow(named: name) else {
            let available = FocusRelayServer.workflows.map(\.name).joined(separator: ", ")
            throw ValidationError("Unknown workflow: \(name). Available workflows: \(available).")
        }
        return workflow
    }

    func renderedOutput() throws -> String {
        try resolveWorkflow().instructions
    }

    func run() throws {
        print(try renderedOutput())
    }
}
