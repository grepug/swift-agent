import AnyLanguageModel
import Foundation

/// Configuration structure for loading agents, models, and MCP servers
public struct AgentConfiguration: Sendable, Codable {
    /// List of model configurations to register
    public let models: [AgentModel]

    /// List of agents to register
    public let agents: [Agent]

    /// MCP server configurations to register
    public let mcpServers: [MCPServerConfiguration]

    public init(
        models: [AgentModel] = [],
        agents: [Agent] = [],
        mcpServers: [MCPServerConfiguration] = []
    ) {
        self.models = models
        self.agents = agents
        self.mcpServers = mcpServers
    }
}
