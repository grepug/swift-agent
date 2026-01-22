import Foundation

/// Protocol for tools that can be called by the agent
public protocol ToolProtocol: Sendable {
    /// Unique name of the tool
    var name: String { get }
    
    /// Description of what the tool does
    var description: String { get }
    
    /// JSON schema for the tool's parameters
    var parameters: AnyCodable { get }
    
    /// Execute the tool with the given arguments
    /// - Parameter arguments: JSON string containing the arguments
    /// - Returns: Result of the tool execution as a string
    func execute(arguments: String) async throws -> String
}

/// Error types for tool execution
public enum ToolError: Error, CustomStringConvertible {
    case toolNotFound(String)
    case invalidArguments(String)
    case executionFailed(String)
    
    public var description: String {
        switch self {
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}
