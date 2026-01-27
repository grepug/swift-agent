import AnyLanguageModel
import Dependencies
import Foundation

/// Represents a session context for executing an agent
public struct AgentSessionContext: Sendable, Codable, Hashable {
    public let agentId: UUID
    public let userId: UUID
    public let sessionId: UUID

    public init(
        agentId: UUID,
        userId: UUID,
        sessionId: UUID = UUID()
    ) {
        self.agentId = agentId
        self.userId = userId
        self.sessionId = sessionId
    }
}

/// The core agent descriptor - immutable definition of an agent's capabilities
public struct Agent: Sendable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let description: String

    package let modelName: String
    package let toolNames: [String]
    package let mcpServerNames: [String]
    package let instructions: String

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        modelName: String,
        instructions: String,
        toolNames: [String] = [],
        mcpServerNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.modelName = modelName
        self.toolNames = toolNames
        self.instructions = instructions
        self.mcpServerNames = mcpServerNames
    }
}

// MARK: - Agent Errors

public enum AgentError: Error, CustomStringConvertible {
    case agentNotFound(UUID)
    case modelNotFound(String)
    case noResponseFromModel
    case invalidConfiguration(String)
    case invalidJSONResponse

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
        }
    }
}
