import Foundation
import Logging

private let logger = Logger(label: "AnyLanguageModel.MCPTool.MCPServer")

/// Represents an MCP (Model Context Protocol) server connection.
///
/// MCP servers should be created and managed through ``MCPServerCenter`` to ensure
/// efficient resource usage and connection reuse.
///
/// ## Example
/// ```swift
/// let config = MCPServerConfiguration(
///     name: "deepwiki",
///     transport: .stdio(
///         command: "npx",
///         arguments: ["-y", "@modelcontextprotocol/server-deepwiki"]
///     )
/// )
///
/// let server = try await MCPServerCenter.shared.server(for: config)
/// let tools = try await server.discover()
/// ```
public actor MCPServer {
    /// The unique name identifying this server.
    public let name: String
    
    /// The configuration used to create this server.
    public let configuration: MCPServerConfiguration
    
    private let transport: any MCPTransport
    private var discoveredTools: [MCPDiscoveredTool] = []
    private var isConnected = false

    /// Creates an MCP server from a configuration.
    ///
    /// - Note: Prefer using ``MCPServerCenter/server(for:)`` to avoid creating
    ///   duplicate connections to the same server.
    ///
    /// - Parameter configuration: The server configuration
    init(configuration: MCPServerConfiguration) {
        self.name = configuration.name
        self.configuration = configuration
        
        switch configuration.transport {
        case .http(let url, let headers):
            logger.info(
                "Creating MCP server with HTTP transport",
                metadata: [
                    "name": "\(configuration.name)",
                    "url": "\(url)",
                ]
            )
            self.transport = MCPHTTPTransport(
                url: url,
                headers: headers,
                urlSession: .shared
            )
            
        case .stdio(let command, let arguments, let environment):
            logger.info(
                "Creating MCP server with stdio transport",
                metadata: [
                    "name": "\(configuration.name)",
                    "command": "\(command)",
                    "argumentCount": "\(arguments.count)",
                ]
            )
            self.transport = MCPStdioTransport(
                command: command,
                arguments: arguments,
                environment: environment
            )
        }
    }

    /// Connects to the MCP server and discovers available tools.
    ///
    /// This is a convenience method that combines initialization and tool discovery.
    ///
    /// - Parameters:
    ///   - timeout: Connection timeout (default: 30 seconds)
    ///   - include: Only include tools matching these names (nil = include all)
    ///   - exclude: Exclude tools matching these names
    /// - Returns: Array of discovered tools conforming to the `Tool` protocol
    public func discover(
        timeout: Duration = .seconds(30),
        include: Set<String>? = nil,
        exclude: Set<String> = []
    ) async throws -> [any Tool] {
        logger.info(
            "Starting tool discovery",
            metadata: [
                "name": "\(name)",
                "timeout": "\(timeout)",
                "hasIncludeFilter": "\(include != nil)",
                "excludeCount": "\(exclude.count)",
            ]
        )

        // Initialize connection if not already connected
        if !isConnected {
            logger.debug("Initializing connection", metadata: ["name": "\(name)"])
            _ = try await transport.initialize(timeout: timeout)
            isConnected = true
            logger.info("Connection initialized", metadata: ["name": "\(name)"])
        }

        // Fetch tool definitions
        logger.debug("Fetching tool definitions", metadata: ["name": "\(name)"])
        let toolDefinitions = try await transport.listTools()
        logger.debug(
            "Fetched tool definitions",
            metadata: [
                "name": "\(name)",
                "names": "\(toolDefinitions.map { $0.name })",
            ]
        )

        // Filter tools
        let filteredDefinitions = toolDefinitions.filter { definition in
            // Check exclusion
            if exclude.contains(definition.name) {
                logger.debug("Excluding tool", metadata: ["toolName": "\(definition.name)"])
                return false
            }

            // Check inclusion (if specified)
            if let include = include {
                let included = include.contains(definition.name)
                if !included {
                    logger.debug("Tool not in include list", metadata: ["toolName": "\(definition.name)"])
                }
                return included
            }

            return true
        }

        logger.info(
            "Tool discovery complete",
            metadata: [
                "name": "\(name)",
                "totalTools": "\(toolDefinitions.count)",
                "discoveredTools": "\(filteredDefinitions.count)",
            ]
        )

        // Create discovered tool wrappers
        discoveredTools = filteredDefinitions.map { definition in
            MCPDiscoveredTool(
                definition: definition,
                transport: transport
            )
        }

        return discoveredTools
    }

    /// Returns the list of already-discovered tools without re-fetching.
    ///
    /// Call `discover()` first to populate this list.
    public func tools() -> [any Tool] {
        return discoveredTools
    }

    /// Closes the connection to the MCP server.
    public func close() async throws {
        logger.info("Closing MCP server connection", metadata: ["name": "\(name)"])
        try await transport.close()
        isConnected = false
        discoveredTools.removeAll()
        logger.debug("Connection closed", metadata: ["name": "\(name)"])
    }
}
