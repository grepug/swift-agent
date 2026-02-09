import Foundation
import Logging

private let logger = Logger(label: "AnyLanguageModel.MCPTool.MCPServerCenter")

/// A centralized manager for MCP server connections.
///
/// `MCPServerCenter` manages the lifecycle of MCP server instances, ensuring
/// that servers with the same configuration are reused rather than creating
/// duplicate connections.
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
/// // Get or create server
/// let server = try await MCPServerCenter.shared.server(for: config)
/// let tools = try await server.discover()
///
/// // Later calls with same config reuse the server
/// let sameServer = try await MCPServerCenter.shared.server(for: config)
/// ```
public actor MCPServerCenter {
    /// Shared singleton instance.
    public static let shared = MCPServerCenter()

    private var servers: [MCPServerConfiguration: MCPServer] = [:]

    private init() {
        logger.info("MCPServerCenter initialized")
    }

    /// Gets an existing server or creates a new one for the given configuration.
    ///
    /// If a server with the same configuration already exists, it will be reused.
    /// Otherwise, a new server instance is created and cached.
    ///
    /// - Parameter configuration: The server configuration
    /// - Returns: An MCP server instance
    /// - Throws: Errors from server initialization
    public func server(for configuration: MCPServerConfiguration) async throws -> MCPServer {
        if let existing = servers[configuration] {
            logger.debug("Reusing existing MCP server", metadata: ["name": "\(configuration.name)"])
            return existing
        }

        logger.info("Creating new MCP server", metadata: ["name": "\(configuration.name)"])
        let server = MCPServer(configuration: configuration)
        servers[configuration] = server
        return server
    }

    /// Removes and closes a server for the given configuration.
    ///
    /// The server is removed from the center and its connection is closed.
    ///
    /// - Parameter configuration: The configuration of the server to remove
    /// - Throws: Errors from closing the server connection
    public func remove(_ configuration: MCPServerConfiguration) async throws {
        guard let server = servers.removeValue(forKey: configuration) else {
            logger.debug("Server not found for removal", metadata: ["name": "\(configuration.name)"])
            return
        }

        logger.info("Removing MCP server", metadata: ["name": "\(configuration.name)"])
        try await server.close()
    }

    /// Removes and closes a server by name.
    ///
    /// - Parameter name: The name of the server to remove
    /// - Throws: Errors from closing the server connection
    public func remove(named name: String) async throws {
        guard let configuration = servers.keys.first(where: { $0.name == name }) else {
            logger.debug("Server not found for removal", metadata: ["name": "\(name)"])
            return
        }

        try await remove(configuration)
    }

    /// Closes all managed servers and clears the cache.
    ///
    /// This method closes all server connections and removes them from the center.
    /// Useful for cleanup during application shutdown.
    ///
    /// - Throws: Errors from closing server connections
    public func closeAll() async throws {
        logger.info("Closing all MCP servers", metadata: ["count": "\(servers.count)"])

        for server in servers.values {
            try await server.close()
        }

        servers.removeAll()
        logger.debug("All servers closed")
    }

    /// Returns the names of all currently managed servers.
    public func serverNames() -> [String] {
        return servers.keys.map { $0.name }
    }

    /// Returns the number of currently managed servers.
    public var count: Int {
        return servers.count
    }
}
