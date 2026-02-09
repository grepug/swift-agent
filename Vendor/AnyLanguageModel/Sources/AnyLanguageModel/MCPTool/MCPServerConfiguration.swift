import Foundation

/// Configuration for an MCP (Model Context Protocol) server.
///
/// Defines how to connect to an MCP server, either via HTTP or stdio transport.
///
/// ## Example
/// ```swift
/// // HTTP server
/// let httpConfig = MCPServerConfiguration(
///     name: "local-api",
///     transport: .http(url: URL(string: "http://localhost:3000")!)
/// )
///
/// // Stdio server (npm package)
/// let stdioConfig = MCPServerConfiguration(
///     name: "deepwiki",
///     transport: .stdio(
///         command: "npx",
///         arguments: ["-y", "@modelcontextprotocol/server-deepwiki"]
///     )
/// )
/// ```
public struct MCPServerConfiguration: Hashable, Sendable, Codable {
    /// A unique identifier for this server configuration.
    public let name: String

    /// The transport configuration for connecting to the server.
    public let transport: TransportConfiguration

    /// Creates a new MCP server configuration.
    ///
    /// - Parameters:
    ///   - name: A unique identifier for this server
    ///   - transport: The transport configuration (HTTP or stdio)
    public init(name: String, transport: TransportConfiguration) {
        self.name = name
        self.transport = transport
    }

    /// Transport configuration for MCP communication.
    public enum TransportConfiguration: Hashable, Sendable, Codable {
        /// HTTP-based transport.
        ///
        /// - Parameters:
        ///   - url: The HTTP endpoint URL
        ///   - headers: Optional HTTP headers (e.g., for authentication)
        case http(url: URL, headers: [String: String] = [:])

        /// Stdio-based transport using a subprocess.
        ///
        /// - Parameters:
        ///   - command: The command to execute (e.g., "npx", "node")
        ///   - arguments: Command-line arguments
        ///   - environment: Additional environment variables
        case stdio(
            command: String,
            arguments: [String] = [],
            environment: [String: String] = [:]
        )
    }
}
