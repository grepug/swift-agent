import AnyLanguageModel
import Dependencies
import Foundation

// MARK: - Protocol

public protocol AgentCenter: Sendable {
    // Agent management
    func register(agent: Agent) async
    func agent(id: String) async -> Agent?
    func prepareAgent(_ id: String) async throws

    // Session management
    func createSession(
        agentId: String,
        userId: UUID,
        name: String?
    ) async throws -> AgentSession

    // Agent execution
    func runAgent<T: Codable & Generable>(
        session: AgentSessionContext,
        message: String,
        as type: T.Type,
        options: AgentRunOptions,
        loadHistory: Bool
    ) async throws -> Run

    func streamAgent(
        session: AgentSessionContext,
        message: String,
        options: AgentRunOptions,
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

    // Hook management
    func register(preHook: RegisteredPreHook) async
    func register(postHook: RegisteredPostHook) async
    func preHook(named name: String) async -> RegisteredPreHook?
    func postHook(named name: String) async -> RegisteredPostHook?

    init()

    /// Loads models, agents, and MCP servers from a configuration object.
    ///
    /// Models defined in the configuration will be automatically registered as OpenAI-compatible
    /// language models. Native Swift tools must still be registered programmatically before
    /// calling this method if they are referenced by agents. MCP servers defined in the config
    /// will be registered automatically.
    ///
    /// **Validation**: This method uses fail-fast validation. If any agent references
    /// a model, tool, or MCP server that doesn't exist, an error will be thrown and no
    /// agents will be loaded.
    ///
    /// Example usage:
    /// ```swift
    /// // Create the agent center
    /// let agentCenter = LiveAgentCenter()
    ///
    /// // Optionally register native Swift tools if referenced by agents
    /// await agentCenter.register(tool: myTool)
    ///
    /// // Load from file
    /// let data = try Data(contentsOf: configURL)
    /// let config = try JSONDecoder().decode(AgentConfiguration.self, from: data)
    /// try await agentCenter.load(configuration: config)
    ///
    /// // Or hardcode configuration
    /// let config = AgentConfiguration(
    ///     models: [
    ///         AgentModel(
    ///             name: "gpt-4",
    ///             baseURL: URL(string: "https://api.openai.com/v1")!,
    ///             id: "gpt-4",
    ///             apiKey: "sk-..."
    ///         )
    ///     ],
    ///     agents: [myAgent],
    ///     mcpServers: [fileSystemConfig]
    /// )
    /// try await agentCenter.load(configuration: config)
    /// ```
    ///
    /// - Parameter configuration: The configuration containing models, agents, and MCP servers
    /// - Throws: `AgentError.invalidConfiguration` if validation fails
    func load(configuration: AgentConfiguration) async throws
}

// MARK: - Dependency

public extension AgentCenter {
    func runAgent<T: Codable & Generable>(
        session: AgentSessionContext,
        message: String,
        as type: T.Type
    ) async throws -> Run {
        try await runAgent(
            session: session,
            message: message,
            as: type,
            options: AgentRunOptions(),
            loadHistory: true
        )
    }

    func runAgent<T: Codable & Generable>(
        session: AgentSessionContext,
        message: String,
        as type: T.Type,
        options: AgentRunOptions
    ) async throws -> Run {
        try await runAgent(
            session: session,
            message: message,
            as: type,
            options: options,
            loadHistory: true
        )
    }

    func runAgent<T: Codable & Generable>(
        session: AgentSessionContext,
        message: String,
        as type: T.Type,
        loadHistory: Bool
    ) async throws -> Run {
        try await runAgent(
            session: session,
            message: message,
            as: type,
            options: AgentRunOptions(),
            loadHistory: loadHistory
        )
    }

    func runAgent(
        session: AgentSessionContext,
        message: String,
        options: AgentRunOptions,
        loadHistory: Bool = true
    ) async throws -> Run {
        try await runAgent(
            session: session,
            message: message,
            as: String.self,
            options: options,
            loadHistory: loadHistory
        )
    }

    func runAgent(
        session: AgentSessionContext,
        message: String,
        loadHistory: Bool = true
    ) async throws -> Run {
        try await runAgent(
            session: session,
            message: message,
            as: String.self,
            options: AgentRunOptions(),
            loadHistory: loadHistory
        )
    }

    func streamAgent(
        session: AgentSessionContext,
        message: String
    ) async -> AsyncThrowingStream<String, Error> {
        await streamAgent(
            session: session,
            message: message,
            options: AgentRunOptions(),
            loadHistory: true
        )
    }

    func streamAgent(
        session: AgentSessionContext,
        message: String,
        loadHistory: Bool
    ) async -> AsyncThrowingStream<String, Error> {
        await streamAgent(
            session: session,
            message: message,
            options: AgentRunOptions(),
            loadHistory: loadHistory
        )
    }

    func streamAgent(
        session: AgentSessionContext,
        message: String,
        options: AgentRunOptions
    ) async -> AsyncThrowingStream<String, Error> {
        await streamAgent(
            session: session,
            message: message,
            options: options,
            loadHistory: true
        )
    }
}

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
