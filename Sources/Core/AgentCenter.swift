import AnyLanguageModel
import Dependencies
import Foundation

// MARK: - Protocol

public protocol AgentCenterProtocol: Sendable {
    // Agent management
    func register(agent: Agent) async
    func agent(id: UUID) async -> Agent?
    func useAgent(id: UUID, sessionId: UUID, userId: UUID) async throws -> Agent
    func prepareAgent(_ id: UUID) async throws

    // Model management (from ModelCenter)
    func register(model: any LanguageModel, named name: String) async
    func model(named name: String) async -> (any LanguageModel)?

    // Tool management (from ToolCenter)
    func register(tool: any Tool) async
    func register(tools: [any Tool]) async
    func tool(named name: String) async -> (any Tool)?

    // MCP configuration management (from ToolCenter)
    func register(mcpServerConfiguration: MCPServerConfiguration) async
    func mcpServerConfiguration(named name: String) async -> MCPServerConfiguration?
}

// MARK: - Live Implementation

actor AgentCenter: AgentCenterProtocol {
    private var agents: [UUID: Agent] = [:]
    private var discoveredAgents: Set<UUID> = []

    // From ModelCenter
    private var models: [String: any LanguageModel] = [:]

    // From ToolCenter
    private var tools: [String: any Tool] = [:]
    private var mcpServerConfigurations: [String: MCPServerConfiguration] = [:]

    init() {}

    // MARK: - Agent Management

    func register(agent: Agent) {
        agents[agent.id] = agent
    }

    func agent(id: UUID) -> Agent? {
        agents[id]
    }

    func useAgent(id: UUID, sessionId: UUID, userId: UUID) async throws -> Agent {
        guard var agent = agents[id] else {
            fatalError("Agent with ID \(id) not found")
        }

        // Lazy discovery on first use
        if !discoveredAgents.contains(id) {
            try await discoverTools(for: id)
            discoveredAgents.insert(id)
        }

        agent.sessionId = sessionId
        agent.userId = userId

        return agent
    }

    func prepareAgent(_ id: UUID) async throws {
        guard !discoveredAgents.contains(id) else { return }
        try await discoverTools(for: id)
        discoveredAgents.insert(id)
    }

    // MARK: - Model Management

    func register(model: any LanguageModel, named name: String) {
        models[name] = model
    }

    func model(named name: String) -> (any LanguageModel)? {
        models[name]
    }

    // MARK: - Tool Management

    func register(tool: any Tool) {
        tools[tool.name] = tool
    }

    func register(tools: [any Tool]) {
        for tool in tools {
            register(tool: tool)
        }
    }

    func tool(named name: String) -> (any Tool)? {
        tools[name]
    }

    // MARK: - MCP Configuration Management

    func register(mcpServerConfiguration: MCPServerConfiguration) {
        mcpServerConfigurations[mcpServerConfiguration.name] = mcpServerConfiguration
    }

    func mcpServerConfiguration(named name: String) -> MCPServerConfiguration? {
        mcpServerConfigurations[name]
    }

    // MARK: - Private Helpers

    private func discoverTools(for agentId: UUID) async throws {
        guard let agent = agents[agentId] else { return }

        guard !agent.mcpServerNames.isEmpty else { return }

        print("Discovering tools for agent: \(agent.name)")

        let discoveredTools = try await withThrowingTaskGroup(of: [any Tool].self) { group in
            for mcpConfigName in agent.mcpServerNames {
                group.addTask {
                    guard let mcpConfig = await self.mcpServerConfiguration(named: mcpConfigName) else {
                        fatalError("MCP Server Configuration with name \(mcpConfigName) not found")
                    }
                    let server = try await MCPServerCenter.shared.server(for: mcpConfig)
                    let tools = try await server.discover()
                    print("Discovered tools from MCP server '\(mcpConfig.name)': \(tools.map { $0.name })")
                    return tools
                }
            }

            var allTools: [any Tool] = []
            for try await tools in group {
                allTools.append(contentsOf: tools)
            }
            return allTools
        }

        // Update agent with discovered tool names
        if var agent = agents[agentId] {
            agent.toolNames.append(contentsOf: discoveredTools.map { $0.name })
            agents[agentId] = agent
            register(tools: discoveredTools)
            print("Registered \(discoveredTools.count) tools for agent '\(agent.name)'")
        }
    }
}

// MARK: - Dependency

extension DependencyValues {
    public var agentCenter: AgentCenterProtocol {
        get { self[AgentCenterKey.self] }
        set { self[AgentCenterKey.self] = newValue }
    }

    private enum AgentCenterKey: DependencyKey {
        static let liveValue: AgentCenterProtocol = AgentCenter()
        static let testValue: AgentCenterProtocol = AgentCenter()
    }
}
