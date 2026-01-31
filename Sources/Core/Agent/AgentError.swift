import Foundation

/// Errors that can occur during agent operations
public enum AgentError: Error, CustomStringConvertible {
    case agentNotFound(String)
    case modelNotFound(String)
    case noResponseFromModel
    case invalidConfiguration(String)
    case invalidJSONResponse
    case sessionNotFound(UUID)

    public var description: String {
        switch self {
        case .agentNotFound(let id):
            return "Agent with ID \(id) not found"
        case .modelNotFound(let name):
            return "Model '\(name)' not registered in AgentCenter"
        case .noResponseFromModel:
            return "No response received from model"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .invalidJSONResponse:
            return "Could not parse JSON from model response"
        case .sessionNotFound(let id):
            return "Session with ID \(id) not found. Create a session first using createSession()."
        }
    }
}
