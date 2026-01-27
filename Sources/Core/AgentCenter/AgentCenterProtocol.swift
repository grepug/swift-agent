import AnyLanguageModel
import Dependencies
import Foundation

// MARK: - Protocol

public protocol AgentCenter: Sendable {
    // Agent management
    func register(agent: Agent) async
    func agent(id: UUID) async -> Agent?
    func prepareAgent(_ id: UUID) async throws

    // Agent execution
    func runAgent<T: Codable & Generable>(
        session: AgentSessionContext,
        message: String,
        as type: T.Type,
        loadHistory: Bool
    ) async throws -> Run

    func streamAgent(
        session: AgentSessionContext,
        message: String,
        loadHistory: Bool
    ) async -> AsyncThrowingStream<String, Error>

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

// MARK: - Dependency

extension DependencyValues {
    public var agentCenter: AgentCenter {
        get { self[AgentCenterKey.self] }
        set { self[AgentCenterKey.self] = newValue }
    }

    private enum AgentCenterKey: DependencyKey {
        static let liveValue: AgentCenter = LiveAgentCenter()
        static let testValue: AgentCenter = LiveAgentCenter()
    }
}
