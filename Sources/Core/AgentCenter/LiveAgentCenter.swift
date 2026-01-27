import AnyLanguageModel
import Dependencies
import Foundation
import Logging

// MARK: - Live Implementation

private let logger = Logger(label: "LiveAgentCenter")

actor LiveAgentCenter: AgentCenter {
    private var agents: [UUID: Agent] = [:]
    private var discoveredMCPServers: Set<String> = []
    private var mcpServerTools: [String: [String]] = [:]  // MCP server name -> tool names

    private var models: [String: any LanguageModel] = [:]
    private var tools: [String: any Tool] = [:]

    private var mcpServerConfigurations: [String: MCPServerConfiguration] = [:]

    @Dependency(\.agentObservers) private var observers

    // Track tool execution IDs by callIndex (for correlating started/completed events)
    private var toolExecutionIds: [Int: UUID] = [:]

    // Track current session for capturing model events
    private var currentRunSession: UUID?

    init() {}

    // MARK: - Event Emission

    private func emit(_ event: AgentCenterEvent) {
        observers.forEach { $0.observe(event) }
    }
}

// MARK: - Agent Management

extension LiveAgentCenter {
    func register(agent: Agent) async {
        logger.info("Registering agent", metadata: ["agent.id": .string(agent.id.uuidString), "agent.name": .string(agent.name)])
        agents[agent.id] = agent
        logger.debug("Agent registered successfully", metadata: ["agent.id": .string(agent.id.uuidString)])
    }

    func agent(id: UUID) async -> Agent? {
        let agent = agents[id]
        if agent != nil {
            logger.debug("Agent found", metadata: ["agent.id": .string(id.uuidString)])
        } else {
            logger.warning("Agent not found", metadata: ["agent.id": .string(id.uuidString)])
        }
        return agent
    }

    func prepareAgent(_ id: UUID) async throws {
        logger.info("Preparing agent", metadata: ["agent.id": .string(id.uuidString)])
        guard let agent = agents[id] else {
            logger.error("Agent not found", metadata: ["agent.id": .string(id.uuidString)])
            throw AgentError.agentNotFound(id)
        }
        try await discoverMCPServers(agent.mcpServerNames)
        logger.info("Agent prepared successfully", metadata: ["agent.id": .string(id.uuidString)])
    }
}

// MARK: - Agent Execution

extension LiveAgentCenter {

    func runAgent<T: Codable & Generable>(
        session: AgentSessionContext,
        message: String,
        as type: T.Type,
        loadHistory: Bool = true
    ) async throws -> Run {
        logger.info("Running agent", metadata: ["agent.id": .string(session.agentId.uuidString), "session.id": .string(session.sessionId.uuidString), "user.id": .string(session.userId.uuidString)])

        // Track current session for model event handling
        currentRunSession = session.sessionId
        defer { currentRunSession = nil }

        // Validate agent exists
        let agent = agents[session.agentId]
        guard let agent else {
            logger.error("Agent not found", metadata: ["agent.id": .string(session.agentId.uuidString)])
            throw AgentError.agentNotFound(session.agentId)
        }

        emit(
            .agentExecutionStarted(
                agent: agent,
                session: session,
                timestamp: Date()
            ))

        do {
            // Discover MCP servers for this agent
            try await discoverMCPServers(agent.mcpServerNames)

            // Load transcript with history
            let transcript = try await loadTranscript(
                for: agent,
                session: session,
                includeHistory: loadHistory
            )

            // Create session with conversation history
            let modelSession = await createSession(for: agent, with: transcript)

            // Use AnyLanguageModel's session to handle the conversation
            // Individual API calls will be tracked via handleModelEvent()
            logger.debug("Sending message to model", metadata: ["agent.name": .string(agent.name), "model.name": .string(agent.modelName)])
            let response = try await modelSession.respond(to: message, generating: T.self)

            let content: Data?

            if let string = response.content as? String {
                // Extract content from response
                logger.debug("Response received as string", metadata: ["agent.id": .string(session.agentId.uuidString)])
                content = string.data(using: .utf8)
            } else {
                logger.debug("Response received as structured type", metadata: ["agent.id": .string(session.agentId.uuidString)])
                content = try JSONEncoder().encode(response.content)
            }

            // Create messages from the session transcript
            let messages = extractMessages(from: modelSession.transcript)
            logger.debug("Messages extracted from transcript", metadata: ["message.count": .stringConvertible(messages.count)])

            // Create run record
            let run = Run(
                agentId: session.agentId,
                sessionId: session.sessionId,
                userId: session.userId,
                messages: messages,
                rawContent: content,
            )

            // Save to storage
            @Dependency(\.storage) var storage
            logger.debug("Saving run to storage", metadata: ["run.id": .string(run.id.uuidString)])
            try await storage.append(run, for: agent)
            logger.info("Agent run completed successfully", metadata: ["run.id": .string(run.id.uuidString), "message.count": .stringConvertible(messages.count)])

            emit(
                .runSaved(
                    runId: run.id,
                    agentId: agent.id,
                    messageCount: messages.count,
                    timestamp: Date()
                ))

            emit(
                .agentExecutionCompleted(
                    run: run,
                    timestamp: Date()
                ))

            return run
        } catch {
            emit(
                .agentExecutionFailed(
                    session: session,
                    error: error,
                    timestamp: Date()
                ))
            throw error
        }
    }

    func streamAgent(
        session: AgentSessionContext,
        message: String,
        loadHistory: Bool = true
    ) async -> AsyncThrowingStream<String, Error> {
        let agentLogger = logger  // Capture logger for use in closure
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    agentLogger.info("Starting agent stream", metadata: ["agent.id": .string(session.agentId.uuidString), "session.id": .string(session.sessionId.uuidString)])

                    // Validate agent exists
                    let agent = agents[session.agentId]
                    guard let agent else {
                        agentLogger.error("Agent not found for stream", metadata: ["agent.id": .string(session.agentId.uuidString)])
                        throw AgentError.agentNotFound(session.agentId)
                    }

                    // Discover MCP servers for this agent
                    try await discoverMCPServers(agent.mcpServerNames)

                    // Load transcript with history
                    let transcript = try await self.loadTranscript(
                        for: agent,
                        session: session,
                        includeHistory: loadHistory
                    )

                    // Create session with history
                    let modelSession = await createSession(for: agent, with: transcript)

                    // Use respond() which handles tool calls automatically
                    logger.debug("Sending stream message to model", metadata: ["agent.name": .string(agent.name), "model.name": .string(agent.modelName)])
                    let response = try await modelSession.respond { Prompt(message) }

                    // The response content is already a String
                    logger.debug("Stream response received", metadata: ["agent.id": .string(session.agentId.uuidString)])
                    continuation.yield(String(describing: response.content))

                    continuation.finish()
                    logger.info("Agent stream completed successfully", metadata: ["agent.id": .string(session.agentId.uuidString), "session.id": .string(session.sessionId.uuidString)])
                } catch {
                    logger.error("Agent stream failed", metadata: ["agent.id": .string(session.agentId.uuidString), "error": .string(String(describing: error))])
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

// MARK: - Model Management

extension LiveAgentCenter {

    func register(model: any LanguageModel, named name: String) async {
        logger.info("Registering language model", metadata: ["model.name": .string(name), "model.type": .string(String(describing: type(of: model)))])
        models[name] = model
        logger.debug("Language model registered successfully", metadata: ["model.name": .string(name)])
    }

    func model(named name: String) async -> (any LanguageModel)? {
        let model = models[name]
        if model != nil {
            logger.debug("Language model found", metadata: ["model.name": .string(name)])
        } else {
            logger.warning("Language model not found", metadata: ["model.name": .string(name)])
        }
        return model
    }
}

// MARK: - Tool Management

extension LiveAgentCenter {

    func register(tool: any Tool) async {
        logger.info("Registering tool", metadata: ["tool.name": .string(tool.name), "tool.description": .string(tool.description)])
        tools[tool.name] = tool
        logger.debug("Tool registered successfully", metadata: ["tool.name": .string(tool.name)])
    }

    func register(tools: [any Tool]) async {
        logger.info("Registering multiple tools", metadata: ["tool.count": .stringConvertible(tools.count)])
        for tool in tools {
            self.tools[tool.name] = tool
        }
        logger.debug("Tools registered successfully", metadata: ["tool.count": .stringConvertible(tools.count), "tools": .stringConvertible(tools.map { $0.name }.joined(separator: ", "))])
    }

    func tool(named name: String) async -> (any Tool)? {
        let tool = tools[name]
        if tool != nil {
            logger.debug("Tool found", metadata: ["tool.name": .string(name)])
        } else {
            logger.warning("Tool not found", metadata: ["tool.name": .string(name)])
        }
        return tool
    }
}

// MARK: - MCP Server Management

extension LiveAgentCenter {

    func register(mcpServerConfiguration: MCPServerConfiguration) async {
        logger.info("Registering MCP server configuration", metadata: ["mcp.server": .string(mcpServerConfiguration.name), "transport": .string(String(describing: mcpServerConfiguration.transport))])
        mcpServerConfigurations[mcpServerConfiguration.name] = mcpServerConfiguration
        logger.debug("MCP server configuration registered successfully", metadata: ["mcp.server": .string(mcpServerConfiguration.name)])
    }

    func mcpServerConfiguration(named name: String) async -> MCPServerConfiguration? {
        let config = mcpServerConfigurations[name]
        if config != nil {
            logger.debug("MCP server configuration found", metadata: ["mcp.server": .string(name)])
        } else {
            logger.warning("MCP server configuration not found", metadata: ["mcp.server": .string(name)])
        }
        return config
    }

    private func discoverMCPServers(_ serverNames: [String]) async throws {
        let undiscoveredServers = serverNames.filter { !discoveredMCPServers.contains($0) }

        guard !undiscoveredServers.isEmpty else {
            logger.debug("All MCP servers already discovered", metadata: ["mcp.servers": .stringConvertible(serverNames.joined(separator: ", "))])
            return
        }

        logger.info("Discovering MCP servers", metadata: ["mcp.servers": .stringConvertible(undiscoveredServers.joined(separator: ", "))])

        emit(
            .mcpServerDiscoveryStarted(
                serverNames: undiscoveredServers,
                timestamp: Date()
            ))

        try await withThrowingTaskGroup(of: (String, [any Tool]).self) { group in
            for serverName in undiscoveredServers {
                group.addTask {
                    do {
                        guard let mcpConfig = await self.mcpServerConfiguration(named: serverName) else {
                            logger.error("MCP server configuration not found", metadata: ["mcp.server": .string(serverName)])
                            throw AgentError.invalidConfiguration("MCP server configuration '\(serverName)' not found")
                        }
                        logger.debug("Connecting to MCP server", metadata: ["mcp.server": .string(serverName)])
                        let server = try await MCPServerCenter.shared.server(for: mcpConfig)
                        let tools = try await server.discover()
                        logger.info(
                            "Tools discovered from MCP server",
                            metadata: ["mcp.server": .string(serverName), "tool.count": .stringConvertible(tools.count), "tools": .stringConvertible(tools.map { $0.name }.joined(separator: ", "))])
                        return (serverName, tools)
                    } catch {
                        await self.emit(
                            .mcpServerDiscoveryFailed(
                                serverName: serverName,
                                error: error,
                                timestamp: Date()
                            ))
                        throw error
                    }
                }
            }

            for try await (serverName, discoveredTools) in group {
                let toolNames = discoveredTools.map { $0.name }
                mcpServerTools[serverName] = toolNames

                for tool in discoveredTools {
                    tools[tool.name] = tool
                }

                discoveredMCPServers.insert(serverName)
                logger.debug("MCP server tools registered", metadata: ["mcp.server": .string(serverName), "tool.count": .stringConvertible(toolNames.count)])

                emit(
                    .mcpServerDiscovered(
                        serverName: serverName,
                        toolNames: toolNames,
                        timestamp: Date()
                    ))
            }
        }
    }
}

// MARK: - Transcript & Session Management

extension LiveAgentCenter {
    private func tools(for agent: Agent) async -> [any Tool] {
        var result: [any Tool] = []
        var allToolNames = Set(agent.toolNames)

        // Add tools from agent's configured MCP servers
        for serverName in agent.mcpServerNames {
            if let serverTools = mcpServerTools[serverName] {
                allToolNames.formUnion(serverTools)
            }
        }

        for toolName in allToolNames {
            if let tool = tools[toolName] {
                result.append(tool)
            } else {
                logger.warning("Tool not found for agent", metadata: ["agent.id": .string(agent.id.uuidString), "tool.name": .string(toolName)])
            }
        }
        logger.debug("Retrieved tools for agent", metadata: ["agent.id": .string(agent.id.uuidString), "tool.count": .stringConvertible(result.count)])
        return result
    }

    private func loadTranscript(
        for agent: Agent,
        session: AgentSessionContext,
        includeHistory: Bool
    ) async throws -> Transcript {
        logger.debug("Loading transcript", metadata: ["agent.id": .string(agent.id.uuidString), "include.history": .stringConvertible(includeHistory)])
        @Dependency(\.storage) var storage
        let previousRuns = includeHistory ? try await storage.runs(for: agent) : []
        logger.debug("Previous runs loaded", metadata: ["agent.id": .string(agent.id.uuidString), "run.count": .stringConvertible(previousRuns.count)])

        emit(
            .transcriptBuildStarted(
                agentId: agent.id,
                previousRunCount: previousRuns.count,
                timestamp: Date()
            ))

        return try await buildTranscript(
            from: previousRuns,
            for: agent
        )
    }

    private func buildTranscript(
        from runs: [Run],
        for agent: Agent
    ) async throws -> Transcript {
        logger.debug("Building transcript from runs", metadata: ["agent.id": .string(agent.id.uuidString), "run.count": .stringConvertible(runs.count)])
        var entries: [Transcript.Entry] = []

        // Add instructions
        let toolDefs = await tools(for: agent).map { Transcript.ToolDefinition(tool: $0) }
        let instructionsEntry = Transcript.Entry.instructions(
            Transcript.Instructions(
                segments: [.text(.init(content: agent.instructions))],
                toolDefinitions: toolDefs
            )
        )
        entries.append(instructionsEntry)

        // Add messages from previous runs
        for run in runs {
            for message in run.messages {
                switch message.role {
                case .user:
                    if let content = message.content {
                        let promptEntry = Transcript.Entry.prompt(
                            Transcript.Prompt(
                                segments: [.text(.init(content: content))],
                                options: GenerationOptions(),
                                responseFormat: nil
                            )
                        )
                        entries.append(promptEntry)
                    }
                case .assistant:
                    if let content = message.content {
                        let responseEntry = Transcript.Entry.response(
                            Transcript.Response(
                                assetIDs: [],
                                segments: [.text(.init(content: content))]
                            )
                        )
                        entries.append(responseEntry)
                    }
                case .system:
                    // System messages are handled via instructions
                    break
                case .tool:
                    // TODO: Reconstruct tool call entries if needed
                    break
                }
            }
        }

        let transcript = Transcript(entries: entries)

        emit(
            .transcriptBuilt(
                transcript: transcript,
                agentId: agent.id,
                toolCount: toolDefs.count,
                timestamp: Date()
            ))

        return transcript
    }

    private func createSession(
        for agent: Agent,
        with transcript: Transcript
    ) async -> LanguageModelSession {
        logger.debug("Creating language model session", metadata: ["agent.id": .string(agent.id.uuidString), "model.name": .string(agent.modelName)])
        guard let model = models[agent.modelName] else {
            logger.error("Model not found", metadata: ["agent.id": .string(agent.id.uuidString), "model.name": .string(agent.modelName)])
            fatalError("Model '\(agent.modelName)' not registered in AgentCenter")
        }

        let sessionTools = await tools(for: agent)
        logger.debug(
            "Language model session created", metadata: ["agent.id": .string(agent.id.uuidString), "model.name": .string(agent.modelName), "tool.count": .stringConvertible(sessionTools.count)])

        emit(
            .sessionCreated(
                agentId: agent.id,
                modelName: agent.modelName,
                toolCount: sessionTools.count,
                timestamp: Date()
            ))

        let session = LanguageModelSession(
            model: model,
            tools: sessionTools,
            transcript: transcript
        )

        // Set up event handler to track tool calls
        session.onEvent = { [weak self] event in
            guard let self = self else { return }

            Task {
                await self.handleModelEvent(event)
            }
        }

        return session
    }

    private func handleModelEvent(_ event: ModelEvent) async {
        switch event.details {
        case .requestStarted(let info):
            // Track the start of an actual API request with full context
            guard currentRunSession != nil else { return }

            logger.debug(
                "API-level model request started",
                metadata: [
                    "transcript_entries": .stringConvertible(info.transcriptEntries.count),
                    "tools": .stringConvertible(info.availableTools.count),
                ])

            // Emit event for individual API-level model call
            emit(
                .modelRequestSending(
                    requestId: event.id,
                    transcript: Transcript(entries: info.transcriptEntries),
                    message: info.promptText,
                    agentId: UUID(),  // We don't have agent context here
                    modelName: event.modelIdentifier,
                    toolCount: info.availableTools.count,
                    timestamp: event.timestamp
                ))

        case .requestCompleted(let info):
            // This fires for EACH actual API call to the model
            guard let sessionId = currentRunSession else { return }

            // Emit response event for this individual API call
            emit(
                .modelResponseReceived(
                    requestId: event.id,
                    content: info.content,
                    agentId: UUID(),  // We don't have agent context here
                    sessionId: sessionId,
                    duration: info.duration,
                    inputTokens: info.tokenUsage?.promptTokens,
                    outputTokens: info.tokenUsage?.completionTokens,
                    timestamp: event.timestamp
                ))

        case .toolCallStarted(let info):
            // Generate execution ID for this call index
            let executionId = UUID()
            toolExecutionIds[info.callIndex] = executionId

            emit(
                .toolExecutionStarted(
                    toolName: info.toolName,
                    arguments: info.arguments,
                    executionId: executionId,
                    timestamp: event.timestamp
                ))

        case .toolCallCompleted(let info):
            // Use the execution ID from the started event
            guard let executionId = toolExecutionIds[info.callIndex] else {
                logger.warning("Tool call completed without matching started event", metadata: ["callIndex": .stringConvertible(info.callIndex)])
                return
            }

            emit(
                .toolExecutionCompleted(
                    executionId: executionId,
                    toolName: info.toolName,
                    result: info.result,
                    duration: info.duration,
                    success: true,
                    timestamp: event.timestamp
                ))

            // Clean up
            toolExecutionIds[info.callIndex] = nil

        case .toolCallFailed(let info):
            // Use the execution ID from the started event
            guard let executionId = toolExecutionIds[info.callIndex] else {
                logger.warning("Tool call failed without matching started event", metadata: ["callIndex": .stringConvertible(info.callIndex)])
                return
            }

            emit(
                .toolExecutionCompleted(
                    executionId: executionId,
                    toolName: info.toolName,
                    result: info.errorDescription,
                    duration: info.duration,
                    success: false,
                    timestamp: event.timestamp
                ))

            // Clean up
            toolExecutionIds[info.callIndex] = nil

        default:
            break
        }
    }

    private func extractMessages(from transcript: Transcript) -> [Message] {
        var messages: [Message] = []

        for entry in transcript {
            switch entry {
            case .instructions(let inst):
                let content = extractTextContent(from: inst.segments)
                if !content.isEmpty {
                    messages.append(.system(content))
                }

            case .prompt(let prompt):
                let content = extractTextContent(from: prompt.segments)
                if !content.isEmpty {
                    messages.append(.user(content))
                }

            case .response(let response):
                let content = extractTextContent(from: response.segments)
                if !content.isEmpty {
                    messages.append(.assistant(content))
                }

            default:
                // TODO: Extract tool calls if needed
                break
            }
        }

        return messages
    }

    private func extractTextContent(from segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined(separator: "\n")
    }
}
