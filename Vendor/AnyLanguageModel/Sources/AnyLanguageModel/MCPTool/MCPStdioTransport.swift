import Foundation
import Logging

private let logger = Logger(label: "AnyLanguageModel.MCPTool.MCPStdioTransport")

/// Stdio-based transport for MCP communication.
///
/// Handles JSON-RPC 2.0 over stdio (standard input/output) using Foundation.Process.
/// Used for local MCP servers like npm packages.
actor MCPStdioTransport: MCPTransport {
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    private var process: Process?
    private var requestId = 1
    private var pendingResponses: [Int: CheckedContinuation<Data, Error>] = [:]
    private var isInitialized = false

    init(command: String, arguments: [String] = [], environment: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }

    /// Initialize the MCP session with the subprocess.
    func initialize(timeout: Duration) async throws -> MCPInitializeResponse {
        guard !isInitialized else {
            logger.debug("Already initialized, returning cached info")
            return MCPInitializeResponse(
                protocolVersion: "2024-11-05",
                capabilities: MCPCapabilities(tools: nil),
                serverInfo: MCPServerInfo(name: "Unknown", version: "Unknown")
            )
        }

        logger.info("Initializing stdio transport", metadata: ["command": "\(command)"])

        // Start subprocess
        try await startProcess()

        // Send initialize request
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": [
                    "name": "AnyLanguageModel",
                    "version": "1.0.0",
                ],
            ] as [String: Any],
            "id": requestId,
        ]
        requestId += 1

        let response = try await sendRequest(body, timeout: timeout)
        let initResponse = try JSONDecoder().decode(MCPInitializeResponseWrapper.self, from: response)

        // Send initialized notification (no response expected)
        try await sendInitializedNotification()

        isInitialized = true
        logger.info(
            "Stdio transport initialized",
            metadata: [
                "protocolVersion": "\(initResponse.result.protocolVersion)",
                "serverName": "\(initResponse.result.serverInfo.name)",
            ]
        )
        return initResponse.result
    }

    /// Sends the InitializedNotification to complete the MCP handshake.
    func sendInitializedNotification() async throws {
        guard let process = process,
            let inputPipe = process.standardInput as? Pipe
        else {
            throw MCPError.serverError("Process not running")
        }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": [:] as [String: Any],
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        var line = String(data: jsonData, encoding: .utf8) ?? ""
        line.append("\n")

        guard let data = line.data(using: .utf8) else {
            throw MCPError.serverError("Failed to encode notification")
        }

        inputPipe.fileHandleForWriting.write(data)
    }

    /// Lists all available tools from the MCP server.
    func listTools() async throws -> [MCPToolDefinition] {
        logger.debug("Listing tools from stdio server")
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/list",
            "params": [:] as [String: Any],
            "id": requestId,
        ]
        requestId += 1

        let response = try await sendRequest(body, timeout: .seconds(30))
        let toolsResponse = try JSONDecoder().decode(MCPListToolsResponse.self, from: response)
        logger.debug("Tools listed", metadata: ["count": "\(toolsResponse.result.tools.count)"])
        return toolsResponse.result.tools
    }

    /// Calls a specific tool on the MCP server.
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPCallToolResult {
        logger.debug("Calling tool via stdio", metadata: ["toolName": "\(name)"])
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments,
            ],
            "id": requestId,
        ]
        requestId += 1

        let response = try await sendRequest(body, timeout: .seconds(60))

        // Decode as the standard response type
        let decoded = try JSONDecoder().decode(MCPCallToolResponse.self, from: response)
        logger.debug(
            "Tool call completed",
            metadata: [
                "toolName": "\(name)",
                "contentCount": "\(decoded.toolResult.content.count)",
                "isError": "\(decoded.toolResult.isError ?? false)",
            ]
        )
        return decoded.toolResult
    }

    /// Close the stdio transport and terminate subprocess.
    func close() async throws {
        guard let process = process else { return }

        logger.info("Closing stdio transport")

        // Try graceful shutdown first
        if let inputPipe = process.standardInput as? Pipe {
            try? inputPipe.fileHandleForWriting.close()
        }

        // Wait a bit for graceful shutdown
        try? await Task.sleep(for: .milliseconds(500))

        // Force terminate if still running
        if process.isRunning {
            logger.debug("Force terminating subprocess")
            process.terminate()
        }

        self.process = nil
        self.isInitialized = false
        self.pendingResponses.removeAll()
        logger.debug("Stdio transport closed")
    }

    // MARK: - Private Helpers

    /// Starts the subprocess and begins reading from stdout.
    private func startProcess() async throws {
        let process = Process()

        // Use shell to execute command (handles PATH lookup for commands like npx)
        process.executableURL = URL(fileURLWithPath: "/bin/sh")

        // Build the command line
        var commandLine = command
        for arg in arguments {
            // Simple shell escaping (quote arguments with spaces)
            if arg.contains(" ") {
                commandLine += " '\(arg)'"
            } else {
                commandLine += " \(arg)"
            }
        }
        process.arguments = ["-c", commandLine]

        // Set environment
        var mergedEnv = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            mergedEnv[key] = value
        }
        process.environment = mergedEnv

        // Set up pipes
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Start the process
        do {
            logger.debug("Starting subprocess")
            try process.run()
            logger.debug("Subprocess started")
        } catch {
            logger.error("Failed to start subprocess", metadata: ["error": "\(String(describing: error))"])
            throw MCPError.connectionFailed(error)
        }

        self.process = process

        // Start reading responses in background
        Task {
            await readResponses(from: outputPipe.fileHandleForReading)
        }
    }

    /// Sends a JSON-RPC request and waits for the response.
    private func sendRequest(_ body: [String: Any], timeout: Duration) async throws -> Data {
        guard let process = process,
            let inputPipe = process.standardInput as? Pipe
        else {
            throw MCPError.serverError("Process not running")
        }

        // Extract request ID
        guard let id = body["id"] as? Int else {
            throw MCPError.serverError("Request missing ID")
        }

        // Write request to stdin as newline-delimited JSON
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        var line = String(data: jsonData, encoding: .utf8) ?? ""
        line.append("\n")

        guard let data = line.data(using: .utf8) else {
            throw MCPError.serverError("Failed to encode request")
        }

        inputPipe.fileHandleForWriting.write(data)

        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation

            // Set timeout
            Task {
                try? await Task.sleep(for: timeout)
                if pendingResponses.removeValue(forKey: id) != nil {
                    continuation.resume(throwing: MCPError.timeout)
                }
            }
        }
    }

    /// Reads responses from stdout in a loop.
    private func readResponses(from fileHandle: FileHandle) async {
        var buffer = Data()

        // Use async bytes sequence for non-blocking reading
        do {
            for try await byte in fileHandle.bytes {
                buffer.append(byte)

                // Process complete lines when we hit a newline
                if byte == UInt8(ascii: "\n") {
                    // Find the newline
                    if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let lineData = buffer.prefix(upTo: newlineIndex)
                        // Remove the line and the newline character
                        let removeCount = min(newlineIndex + 1, buffer.count)
                        buffer.removeFirst(removeCount)

                        // Skip empty lines
                        if lineData.isEmpty {
                            continue
                        }

                        // Parse JSON-RPC response
                        guard let jsonObject = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                            let id = jsonObject["id"] as? Int
                        else {
                            // Skip non-response messages (notifications, errors without ID)
                            continue
                        }

                        // Resume the continuation waiting for this response
                        if let continuation = pendingResponses.removeValue(forKey: id) {
                            continuation.resume(returning: lineData)
                        }
                    }
                }
            }
        } catch {
            // Stream ended or error occurred
        }
    }
}
