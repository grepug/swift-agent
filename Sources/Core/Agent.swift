import AnyLanguageModel
import Dependencies
import Foundation

// MARK: - Agent Configuration

/// Represents a language model configuration that can be converted to an OpenAILanguageModel
public struct AgentModel: Sendable, Codable, Hashable {
    /// The name/identifier for this model (e.g., "gpt-4", "claude-3-sonnet")
    public let name: String

    /// The base URL for the API endpoint
    public let baseURL: URL

    /// The model ID to use with the API
    public let id: String

    /// The API key for authentication
    public let apiKey: String

    public init(
        name: String,
        baseURL: URL,
        id: String,
        apiKey: String
    ) {
        self.name = name
        self.baseURL = baseURL
        self.id = id
        self.apiKey = apiKey
    }
}

/// Configuration structure for loading agents, tools, models, and MCP servers
public struct AgentConfiguration: Sendable, Codable {
    /// List of model configurations to register
    public let models: [AgentModel]

    /// List of agents to register
    public let agents: [Agent]

    /// List of tool names (for reference/validation)
    public let tools: [String]

    /// MCP server configurations to register
    public let mcpServers: [MCPServerConfiguration]

    public init(
        models: [AgentModel] = [],
        agents: [Agent] = [],
        tools: [String] = [],
        mcpServers: [MCPServerConfiguration] = []
    ) {
        self.models = models
        self.agents = agents
        self.tools = tools
        self.mcpServers = mcpServers
    }
}

// MARK: - Agent Session Context

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
