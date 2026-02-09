import Foundation

/// Errors that can occur during MCP operations.
public enum MCPError: Error, LocalizedError {
    /// The MCP server returned an error response
    case serverError(String)

    /// The tool execution failed on the server
    case toolExecutionError(String)

    /// The HTTP response was invalid
    case invalidResponse

    /// HTTP request failed with status code
    case httpError(Int)

    /// Failed to decode the response
    case decodingError(Error)

    /// Connection to the server failed
    case connectionFailed(Error)

    /// Operation timed out
    case timeout

    public var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return "MCP server error: \(message)"
        case .toolExecutionError(let message):
            return "Tool execution failed: \(message)"
        case .invalidResponse:
            return "Invalid MCP response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .timeout:
            return "Operation timed out"
        }
    }
}
