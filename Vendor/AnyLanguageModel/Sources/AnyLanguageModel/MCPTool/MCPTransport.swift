import Foundation

/// Protocol for MCP transport layers
///
/// Abstracts the underlying communication mechanism (HTTP, stdio, etc.)
/// for the Model Context Protocol.
protocol MCPTransport: Actor {
    /// Initialize connection to the MCP server
    func initialize(timeout: Duration) async throws -> MCPInitializeResponse

    /// Send initialized notification to complete handshake
    func sendInitializedNotification() async throws

    /// List all available tools from the server
    func listTools() async throws -> [MCPToolDefinition]

    /// Call a specific tool with arguments
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPCallToolResult

    /// Close the transport connection
    func close() async throws
}

/// Response from MCP initialize request
struct MCPInitializeResponse: Codable, Sendable {
    let protocolVersion: String
    let capabilities: MCPCapabilities
    let serverInfo: MCPServerInfo
}

struct MCPCapabilities: Codable, Sendable {
    let tools: MCPToolsCapability?

    struct MCPToolsCapability: Codable, Sendable {
        let listChanged: Bool?
    }
}

struct MCPServerInfo: Codable, Sendable {
    let name: String
    let version: String
}

/// Result from calling a tool (Sendable)
struct MCPCallToolResult: Sendable, Decodable {
    let content: [MCPContent]
    let isError: Bool?
}

/// Content returned by MCP tools
struct MCPContent: Sendable, Decodable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?
}
