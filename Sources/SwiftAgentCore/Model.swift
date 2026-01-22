import Foundation

/// Protocol for language models that can generate responses
public protocol ModelProtocol: Sendable {
    /// Generate a response based on the conversation history
    /// - Parameter messages: The conversation messages
    /// - Returns: A model response with content or tool calls
    func generate(messages: [Message]) async throws -> ModelResponse
}

/// Error types for model operations
public enum ModelError: Error, CustomStringConvertible {
    case invalidResponse
    case rateLimitExceeded
    case apiError(String)
    case invalidConfiguration(String)
    
    public var description: String {
        switch self {
        case .invalidResponse:
            return "Invalid response from model"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}
