import Foundation

public actor StdioMCPBurstTransport: BridgeBurstTransport {
    private let serverPath: String
    private let currentDirectory: String
    private let broker = MCPResponseBroker()
    private let encoder: JSONEncoder

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?

    public init(serverPath: String, currentDirectory: String) {
        self.serverPath = serverPath
        self.currentDirectory = currentDirectory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    public func start() async throws {
        guard process == nil else { return }

        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = ["serve"]
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let broker = broker
        process.terminationHandler = { process in
            let status = process.terminationStatus
            Task { @concurrent in
                await broker.finish(.processExit(status))
            }
        }

        let outputHandle = standardOutput.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @concurrent in
                await broker.receive(chunk: data)
            }
        }

        let errorHandle = standardError.fileHandleForReading
        errorHandle.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            throw BridgeBurstTransportError.processExit(-1)
        }

        self.process = process
        inputHandle = standardInput.fileHandleForWriting
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
    }

    public func initialize(timeout: Duration) async throws {
        let requestID = 1
        try await broker.expect(requestID)
        try write(try encoder.encode(InitializeEnvelope(id: requestID)))
        let response = try await broker.response(for: requestID, timeout: timeout)
        guard MCPResponseClassifier.classify(response) == .success else {
            throw BridgeBurstTransportError.protocolError
        }
        try write(try encoder.encode(InitializedEnvelope()))
    }

    public func call(
        _ request: BridgeBurstRequest,
        timeout: Duration
    ) async throws -> BridgeBurstClassification {
        try await broker.expect(request.id)
        do {
            try write(try encoder.encode(ToolCallEnvelope(request: request)))
        } catch {
            await broker.finish(.processExit(-1))
            throw BridgeBurstTransportError.processExit(-1)
        }
        do {
            let response = try await broker.response(for: request.id, timeout: timeout)
            return MCPResponseClassifier.classify(response)
        } catch {
            try? write(try encoder.encode(CancelledEnvelope(requestID: request.id)))
            throw error
        }
    }

    public func stop() async {
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        try? inputHandle?.close()

        if let process, process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        await broker.finish(.processExit(process?.terminationStatus ?? 0))
        inputHandle = nil
        outputHandle = nil
        errorHandle = nil
        process = nil
    }

    private func write(_ data: Data) throws {
        guard let inputHandle else {
            throw BridgeBurstTransportError.processExit(-1)
        }
        var line = data
        line.append(0x0A)
        try inputHandle.write(contentsOf: line)
    }
}

private struct InitializeEnvelope: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method = "initialize"
    let params = InitializeParameters()
}

private struct InitializeParameters: Encodable {
    let protocolVersion = "2025-06-18"
    let capabilities = EmptyObject()
    let clientInfo = ClientInformation()
}

private struct ClientInformation: Encodable {
    let name = "focusrelay-bridge-burst"
    let version = "1"
}

private struct InitializedEnvelope: Encodable {
    let jsonrpc = "2.0"
    let method = "notifications/initialized"
    let params = EmptyObject()
}

private struct CancelledEnvelope: Encodable {
    let jsonrpc = "2.0"
    let method = "notifications/cancelled"
    let params: CancelledParameters

    init(requestID: Int) {
        params = CancelledParameters(
            requestId: requestID,
            reason: "bridge-burst response deadline expired"
        )
    }
}

private struct CancelledParameters: Encodable {
    let requestId: Int
    let reason: String
}

private struct EmptyObject: Encodable {}

private struct ToolCallEnvelope: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method = "tools/call"
    let params: ToolCallParameters

    init(request: BridgeBurstRequest) {
        id = request.id
        params = ToolCallParameters(
            name: request.toolName,
            arguments: request.arguments
        )
    }
}

private struct ToolCallParameters: Encodable {
    let name: String
    let arguments: BurstJSONValue
}
