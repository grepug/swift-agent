import Foundation
import Logging

private let logger = Logger(label: "AnyLanguageModel.MCPTool.MCPHTTPTransport")

/// HTTP-based transport for MCP communication.
///
/// Handles JSON-RPC 2.0 over HTTP with Server-Sent Events (SSE) support.
/// Manages session IDs and the initialization handshake.
actor MCPHTTPTransport: MCPTransport {
    let url: URL
    let headers: [String: String]
    private var requestId = 1
    private let urlSession: URLSession
    private var sessionId: String?
    private var isInitialized = false

    init(url: URL, headers: [String: String], urlSession: URLSession = .shared) {
        self.url = url
        self.headers = headers
        self.urlSession = urlSession
    }

    /// Initialize the MCP session with the server.
    func initialize(timeout: Duration) async throws -> MCPInitializeResponse {
        guard !isInitialized else {
            logger.debug("Already initialized, returning cached info")
            return MCPInitializeResponse(
                protocolVersion: "2024-11-05",
                capabilities: MCPCapabilities(tools: nil),
                serverInfo: MCPServerInfo(name: "Unknown", version: "Unknown")
            )
        }

        logger.info("Initializing HTTP transport", metadata: ["url": "\(url)"])

        // Build request without session ID
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        // Add custom headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // JSON-RPC initialize request
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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Execute request
        let (data, response) = try await urlSession.data(for: request)

        // Extract session ID from response headers
        if let httpResponse = response as? HTTPURLResponse,
            let mcpSessionId = httpResponse.value(forHTTPHeaderField: "mcp-session-id")
        {
            sessionId = mcpSessionId
        } else {
            // Generate fallback session ID if not provided
            sessionId = UUID().uuidString
        }

        // Parse initialize response - handle SSE format if present
        let initResponse: MCPInitializeResponse
        if let httpResponse = response as? HTTPURLResponse,
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
            contentType.contains("text/event-stream")
        {
            // Parse SSE format
            guard let responseString = String(data: data, encoding: .utf8) else {
                throw MCPError.decodingError(
                    NSError(
                        domain: "MCPHTTPTransport",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decode SSE response"]
                    )
                )
            }

            // Extract JSON from SSE format (lines starting with "data: ")
            let lines = responseString.components(separatedBy: "\n")
            var responseWrapper: MCPInitializeResponseWrapper?
            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    if let jsonData = jsonString.data(using: .utf8) {
                        responseWrapper = try? JSONDecoder().decode(MCPInitializeResponseWrapper.self, from: jsonData)
                        if responseWrapper != nil {
                            break
                        }
                    }
                }
            }

            guard let wrapper = responseWrapper else {
                throw MCPError.invalidResponse
            }
            initResponse = wrapper.result
        } else {
            // Parse standard JSON response
            let wrapper = try JSONDecoder().decode(MCPInitializeResponseWrapper.self, from: data)
            initResponse = wrapper.result
        }

        // Send InitializedNotification to complete handshake (MCP protocol requirement)
        try await sendInitializedNotification()

        isInitialized = true
        logger.info(
            "HTTP transport initialized",
            metadata: [
                "protocolVersion": "\(initResponse.protocolVersion)",
                "serverName": "\(initResponse.serverInfo.name)",
                "sessionId": "\(sessionId ?? "none")",
            ]
        )
        return initResponse
    }

    /// Sends the InitializedNotification to complete the MCP handshake.
    func sendInitializedNotification() async throws {
        guard let sessionId = sessionId else {
            throw MCPError.serverError("No session ID available for initialized notification")
        }

        // Build request with session ID
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")

        // Add custom headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // JSON-RPC initialized notification (no params needed)
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": [:] as [String: Any],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Execute request (expect 202 Accepted or similar)
        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw MCPError.serverError("InitializedNotification failed")
        }
    }

    /// Lists all available tools from the MCP server.
    func listTools() async throws -> [MCPToolDefinition] {
        logger.debug("Listing tools from HTTP server")
        let response: MCPListToolsResponse = try await call(
            method: "tools/list",
            params: [:]
        )
        logger.debug("Tools listed", metadata: ["count": "\(response.result.tools.count)"])
        return response.result.tools
    }

    /// Calls a specific tool on the MCP server.
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPCallToolResult {
        logger.debug("Calling tool via HTTP", metadata: ["toolName": "\(name)"])
        let response: MCPCallToolResponse = try await call(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": arguments,
            ]
        )

        logger.debug(
            "Tool call completed",
            metadata: [
                "toolName": "\(name)",
                "contentCount": "\(response.toolResult.content.count)",
                "isError": "\(response.toolResult.isError ?? false)",
            ]
        )

        return response.toolResult
    }

    /// Close the HTTP transport connection.
    func close() async throws {
        // HTTP transport doesn't need explicit cleanup
        isInitialized = false
        sessionId = nil
    }

    /// Makes a JSON-RPC 2.0 call to the MCP server.
    private func call<T: Decodable>(
        method: String,
        params: [String: Any],
        includeSessionId: Bool = true
    ) async throws -> T {
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        // Add session ID if requested and available
        if includeSessionId, let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        // Add custom headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // JSON-RPC 2.0 request body
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": requestId,
        ]
        requestId += 1

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Execute request
        let (data, response) = try await urlSession.data(for: request)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            logger.error(
                "HTTP error",
                metadata: [
                    "statusCode": "\(httpResponse.statusCode)",
                    "method": "\(method)",
                ]
            )
            throw MCPError.httpError(httpResponse.statusCode)
        }

        // Check if response is SSE (Server-Sent Events)
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            // Parse SSE format: data: {...}\n\n
            guard let responseString = String(data: data, encoding: .utf8) else {
                throw MCPError.decodingError(
                    NSError(
                        domain: "MCPHTTPTransport",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decode SSE response"]
                    )
                )
            }

            // Extract JSON from SSE format (lines starting with "data: ")
            let lines = responseString.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))  // Remove "data: " prefix
                    guard let jsonData = jsonString.data(using: .utf8) else { continue }

                    do {
                        return try JSONDecoder().decode(T.self, from: jsonData)
                    } catch {
                        // Try next line if this one fails
                        continue
                    }
                }
            }
            throw MCPError.decodingError(
                NSError(
                    domain: "MCPHTTPTransport",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No valid JSON found in SSE response"]
                )
            )
        }

        // Decode standard JSON response
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Check for JSON-RPC error response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorObj = json["error"] as? [String: Any],
                let message = errorObj["message"] as? String
            {
                logger.error(
                    "MCP JSON-RPC error",
                    metadata: [
                        "method": "\(method)",
                        "error": "\(message)",
                    ]
                )
                throw MCPError.serverError("MCP Error: \(message)")
            }

            logger.error(
                "Decoding error",
                metadata: [
                    "method": "\(method)",
                    "error": "\(String(describing: error))",
                ]
            )
            throw MCPError.decodingError(error)
        }
    }
}

// MARK: - Response Types

/// Wrapper for initialize response
struct MCPInitializeResponseWrapper: Decodable {
    let result: MCPInitializeResponse
}

/// Response from tools/list endpoint
struct MCPListToolsResponse: Decodable {
    struct Result: Decodable {
        let tools: [MCPToolDefinition]
    }
    let result: Result
}

/// Response from tools/call endpoint
// MARK: - Response Types

struct MCPCallToolResponse: Decodable {
    struct NestedResult: Decodable {
        let toolResult: MCPCallToolResult
    }

    enum CodingKeys: String, CodingKey {
        case result
    }

    let toolResult: MCPCallToolResult

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try new format first (result.toolResult.content)
        if let nested = try? container.decode(NestedResult.self, forKey: .result) {
            self.toolResult = nested.toolResult
        }
        // Fall back to old format (result.content directly)
        else {
            self.toolResult = try container.decode(MCPCallToolResult.self, forKey: .result)
        }
    }
}
