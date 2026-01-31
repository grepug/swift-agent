import AnyLanguageModel
import Dependencies
import Foundation
import Logging

// MARK: - Live Implementation

private let logger = Logger(label: "LiveAgentCenter")

actor LiveAgentCenter: AgentCenter {
    private var agents: [String: Agent] = [:]
    private var discoveredMCPServers: Set<String> = []
    private var mcpServerTools: [String: [String]] = [:]  // MCP server name -> tool names

    private var models: [String: any LanguageModel] = [:]
    private var tools: [String: any Tool] = [:]

    private var mcpServerConfigurations: [String: MCPServerConfiguration] = [:]

    // Hook management
    private var preHooks: [String: RegisteredPreHook] = [:]
    private var postHooks: [String: RegisteredPostHook] = [:]
    private var backgroundHookTasks: [UUID: Task<Void, Never>] = [:]

    @Dependency(\.agentObservers) private var observers

    init() {}

    // MARK: - Event Emission

    private func emit(_ event: AgentCenterEvent) {
        observers.forEach { $0.observe(event) }
    }
}

// MARK: - Loading from Configuration

extension LiveAgentCenter {
    func load(configuration: AgentConfiguration) async throws {
        logger.info(
            "Loading agent configuration",
            metadata: [
                "model.count": .stringConvertible(configuration.models.count),
                "agent.count": .stringConvertible(configuration.agents.count),
                "mcp.count": .stringConvertible(configuration.mcpServers.count),
            ])

        // Step 1: Validate for duplicates within the configuration

        try validateNoDuplicateModels(in: configuration)
        try validateNoDuplicateMCPServers(in: configuration)
        try validateNoDuplicateAgents(in: configuration)

        // Step 2: Check for conflicts with already registered items

        try checkForModelConflicts(in: configuration)
        try checkForMCPServerConflicts(in: configuration)
        try checkForAgentConflicts(in: configuration)

        // Step 3: Validate all agent references (before registering anything)

        try await validateAgentReferences(in: configuration)

        // Step 4: All validations passed - now register everything

        await registerModels(from: configuration)
        await registerMCPServers(from: configuration)
        await registerAgents(from: configuration)

        logger.info(
            "Agent configuration loaded successfully",
            metadata: [
                "model.count": .stringConvertible(configuration.models.count),
                "agent.count": .stringConvertible(configuration.agents.count),
                "mcp.count": .stringConvertible(configuration.mcpServers.count),
            ])
    }

    // MARK: - Validation Helpers

    private func validateNoDuplicateModels(in configuration: AgentConfiguration) throws {
        let modelNames = configuration.models.map { $0.name }
        let duplicates = Set(modelNames.filter { name in modelNames.filter { $0 == name }.count > 1 })
        if !duplicates.isEmpty {
            throw AgentError.invalidConfiguration(
                "Duplicate model names found in configuration: \(duplicates.sorted().joined(separator: ", "))"
            )
        }
    }

    private func validateNoDuplicateMCPServers(in configuration: AgentConfiguration) throws {
        let serverNames = configuration.mcpServers.map { $0.name }
        let duplicates = Set(serverNames.filter { name in serverNames.filter { $0 == name }.count > 1 })
        if !duplicates.isEmpty {
            throw AgentError.invalidConfiguration(
                "Duplicate MCP server names found in configuration: \(duplicates.sorted().joined(separator: ", "))"
            )
        }
    }

    private func validateNoDuplicateAgents(in configuration: AgentConfiguration) throws {
        let agentIDs = configuration.agents.map { $0.id }
        let duplicates = Set(agentIDs.filter { id in agentIDs.filter { $0 == id }.count > 1 })
        if !duplicates.isEmpty {
            throw AgentError.invalidConfiguration(
                "Duplicate agent IDs found in configuration: \(duplicates.sorted().joined(separator: ", "))"
            )
        }
    }

    private func checkForModelConflicts(in configuration: AgentConfiguration) throws {
        let existingModelNames = Set(models.keys)
        let newModelNames = Set(configuration.models.map { $0.name })
        let conflicts = newModelNames.intersection(existingModelNames)

        if !conflicts.isEmpty {
            throw AgentError.invalidConfiguration(
                "Configuration contains model names that are already registered: \(conflicts.sorted().joined(separator: ", ")). Unregister them first or use different names."
            )
        }
    }

    private func checkForMCPServerConflicts(in configuration: AgentConfiguration) throws {
        let existingServerNames = Set(mcpServerConfigurations.keys)
        let newServerNames = Set(configuration.mcpServers.map { $0.name })
        let conflicts = newServerNames.intersection(existingServerNames)

        if !conflicts.isEmpty {
            throw AgentError.invalidConfiguration(
                "Configuration contains MCP server names that are already registered: \(conflicts.sorted().joined(separator: ", ")). Unregister them first or use different names."
            )
        }
    }

    private func checkForAgentConflicts(in configuration: AgentConfiguration) throws {
        let existingAgentIDs = Set(agents.keys)
        let newAgentIDs = Set(configuration.agents.map { $0.id })
        let conflicts = newAgentIDs.intersection(existingAgentIDs)

        if !conflicts.isEmpty {
            throw AgentError.invalidConfiguration(
                "Configuration contains agent IDs that are already registered: \(conflicts.sorted().joined(separator: ", ")). Unregister them first or use different IDs."
            )
        }
    }

    private func validateAgentReferences(in configuration: AgentConfiguration) async throws {
        // Collect all model names that will be available (existing + new from config)
        let availableModelNames = Set(models.keys).union(configuration.models.map { $0.name })

        // Collect all MCP server names that will be available (existing + new from config)
        let availableMCPServerNames = Set(mcpServerConfigurations.keys).union(configuration.mcpServers.map { $0.name })

        // Validate each agent's references
        for agent in configuration.agents {
            // Validate model reference
            if !availableModelNames.contains(agent.modelName) {
                throw AgentError.invalidConfiguration(
                    "Agent '\(agent.name)' references unknown model '\(agent.modelName)'. Ensure it's defined in the 'models' array or registered beforehand."
                )
            }

            // Validate tool references (only checking explicitly listed tools, not MCP tools)
            for toolName in agent.toolNames {
                if await tool(named: toolName) == nil {
                    throw AgentError.invalidConfiguration(
                        "Agent '\(agent.name)' references unknown tool '\(toolName)'. Register the tool before loading the config."
                    )
                }
            }

            // Validate MCP server references
            for mcpServerName in agent.mcpServerNames {
                if !availableMCPServerNames.contains(mcpServerName) {
                    throw AgentError.invalidConfiguration(
                        "Agent '\(agent.name)' references unknown MCP server '\(mcpServerName)'. Ensure it's defined in the 'mcpServers' array or registered beforehand."
                    )
                }
            }
        }
    }

    // MARK: - Registration Helpers

    private func registerModels(from configuration: AgentConfiguration) async {
        for modelConfig in configuration.models {
            let openAIModel = OpenAILanguageModel(
                baseURL: modelConfig.baseURL,
                apiKey: modelConfig.apiKey,
                model: modelConfig.id
            )
            await register(model: openAIModel, named: modelConfig.name)
        }
    }

    private func registerMCPServers(from configuration: AgentConfiguration) async {
        for mcpConfig in configuration.mcpServers {
            await register(mcpServerConfiguration: mcpConfig)
        }
    }

    private func registerAgents(from configuration: AgentConfiguration) async {
        for agent in configuration.agents {
            await register(agent: agent)
        }
    }
}

// MARK: - Agent Management

extension LiveAgentCenter {
    func register(agent: Agent) async {
        logger.info("Registering agent", metadata: ["agent.id": .string(agent.id), "agent.name": .string(agent.name)])
        agents[agent.id] = agent
        logger.debug("Agent registered successfully", metadata: ["agent.id": .string(agent.id)])
    }

    func agent(id: String) async -> Agent? {
        let agent = agents[id]
        if agent != nil {
            logger.debug("Agent found", metadata: ["agent.id": .string(id)])
        } else {
            logger.warning("Agent not found", metadata: ["agent.id": .string(id)])
        }
        return agent
    }

    func prepareAgent(_ id: String) async throws {
        logger.info("Preparing agent", metadata: ["agent.id": .string(id)])
        guard let agent = agents[id] else {
            logger.error("Agent not found", metadata: ["agent.id": .string(id)])
            throw AgentError.agentNotFound(id)
        }
        try await discoverMCPServers(agent.mcpServerNames)
        logger.info("Agent prepared successfully", metadata: ["agent.id": .string(id)])
    }

    func createSession(
        agentId: String,
        userId: UUID,
        name: String? = nil
    ) async throws -> AgentSession {
        logger.info(
            "Creating session",
            metadata: [
                "agent.id": .string(agentId),
                "user.id": .string(userId.uuidString),
                "name": .string(name ?? "unnamed"),
            ])

        // Validate agent exists
        guard agents[agentId] != nil else {
            logger.error("Cannot create session for non-existent agent", metadata: ["agent.id": .string(agentId)])
            throw AgentError.agentNotFound(agentId)
        }

        let session = AgentSession(
            agentId: agentId,
            userId: userId,
            name: name
        )

        @Dependency(\.storage) var storage
        let createdSession = try await storage.upsertSession(session)

        logger.info(
            "Session created successfully",
            metadata: [
                "session.id": .string(createdSession.id.uuidString),
                "agent.id": .string(agentId),
            ])

        return createdSession
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
        logger.info("Running agent", metadata: ["agent.id": .string(session.agentId), "session.id": .string(session.sessionId.uuidString), "user.id": .string(session.userId.uuidString)])

        // Validate agent exists
        let agent = agents[session.agentId]
        guard let agent else {
            logger.error("Agent not found", metadata: ["agent.id": .string(session.agentId)])
            throw AgentError.agentNotFound(session.agentId)
        }

        emit(
            .agentExecutionStarted(
                agent: agent,
                session: session,
                timestamp: Date()
            ))

        do {
            // Build hook context
            var hookContext = HookContext(
                agent: agent,
                session: session,
                userMessage: message,
                metadata: [:]
            )

            // Execute pre-hooks (may modify hookContext.userMessage)
            try await executePreHooks(for: agent, context: &hookContext)

            // Use the potentially modified message
            let finalMessage = hookContext.userMessage

            // Discover MCP servers for this agent
            try await discoverMCPServers(agent.mcpServerNames)

            // Load transcript with history
            let transcript = try await loadTranscript(
                for: agent,
                session: session,
                includeHistory: loadHistory
            )

            // Create session with conversation history
            let modelSession = await createSession(for: agent, sessionId: session.sessionId, with: transcript)

            // Use AnyLanguageModel's session to handle the conversation
            // Individual API calls will be tracked via handleModelEvent()
            logger.debug("Sending message to model", metadata: ["agent.name": .string(agent.name), "model.name": .string(agent.modelName)])

            // Track the number of entries before responding to identify new messages
            let entriesBeforeResponse = modelSession.transcript.count

            let response = try await modelSession.respond(to: finalMessage, generating: T.self)

            let content: Data?

            if let string = response.content as? String {
                // Extract content from response
                logger.debug("Response received as string", metadata: ["agent.id": .string(session.agentId)])
                content = string.data(using: String.Encoding.utf8)
            } else {
                logger.debug("Response received as structured type", metadata: ["agent.id": .string(session.agentId)])
                content = try JSONEncoder().encode(response.content)
            }

            // Extract only NEW messages from this turn (entries added after responding)
            let newEntries = Array(modelSession.transcript.dropFirst(entriesBeforeResponse))
            let messages = extractMessages(from: Transcript(entries: newEntries))
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

            // Verify session exists
            guard
                try await storage.getSession(
                    sessionId: session.sessionId,
                    agentId: session.agentId,
                    userId: session.userId
                ) != nil
            else {
                logger.error(
                    "Session not found",
                    metadata: [
                        "session.id": .string(session.sessionId.uuidString),
                        "agent.id": .string(session.agentId),
                    ])
                throw AgentError.sessionNotFound(session.sessionId)
            }

            try await storage.appendRun(run, sessionId: session.sessionId)
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

            // Execute post-hooks (after run is complete and saved)
            await executePostHooks(for: agent, context: hookContext, run: run)

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
                    agentLogger.info("Starting agent stream", metadata: ["agent.id": .string(session.agentId), "session.id": .string(session.sessionId.uuidString)])

                    // Validate agent exists
                    let agent = agents[session.agentId]
                    guard let agent else {
                        agentLogger.error("Agent not found for stream", metadata: ["agent.id": .string(session.agentId)])
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
                    let modelSession = await createSession(for: agent, sessionId: session.sessionId, with: transcript)

                    // Use respond() which handles tool calls automatically
                    logger.debug("Sending stream message to model", metadata: ["agent.name": .string(agent.name), "model.name": .string(agent.modelName)])
                    let response = try await modelSession.respond { Prompt(message) }

                    // The response content is already a String
                    logger.debug("Stream response received", metadata: ["agent.id": .string(session.agentId)])
                    continuation.yield(String(describing: response.content))

                    continuation.finish()
                    logger.info("Agent stream completed successfully", metadata: ["agent.id": .string(session.agentId), "session.id": .string(session.sessionId.uuidString)])
                } catch {
                    logger.error("Agent stream failed", metadata: ["agent.id": .string(session.agentId), "error": .string(String(describing: error))])
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
                logger.warning("Tool not found for agent", metadata: ["agent.id": .string(agent.id), "tool.name": .string(toolName)])
            }
        }
        logger.debug("Retrieved tools for agent", metadata: ["agent.id": .string(agent.id), "tool.count": .stringConvertible(result.count)])
        return result
    }

    private func loadTranscript(
        for agent: Agent,
        session: AgentSessionContext,
        includeHistory: Bool
    ) async throws -> Transcript {
        logger.debug("Loading transcript", metadata: ["agent.id": .string(agent.id), "include.history": .stringConvertible(includeHistory)])
        @Dependency(\.storage) var storage

        // Load runs only from the current session, not from all sessions
        let previousRuns: [Run]
        if includeHistory {
            if let currentSession = try await storage.getSession(
                sessionId: session.sessionId,
                agentId: agent.id,
                userId: session.userId
            ) {
                previousRuns = currentSession.runs
            } else {
                previousRuns = []
            }
        } else {
            previousRuns = []
        }

        logger.debug("Previous runs loaded", metadata: ["agent.id": .string(agent.id), "run.count": .stringConvertible(previousRuns.count)])

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
        logger.debug("Building transcript from runs", metadata: ["agent.id": .string(agent.id), "run.count": .stringConvertible(runs.count)])
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
                    // Handle both text responses and tool calls
                    if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                        // Reconstruct assistant message with tool calls
                        let transcriptCalls = toolCalls.compactMap { tc -> Transcript.ToolCall? in
                            // Convert stored string arguments back to GeneratedContent
                            guard let data = tc.arguments.data(using: .utf8),
                                let decodedContent = try? JSONDecoder().decode(GeneratedContent.self, from: data)
                            else {
                                // Fallback: wrap plain string as GeneratedContent
                                return Transcript.ToolCall(
                                    id: tc.id,
                                    toolName: tc.name,
                                    arguments: GeneratedContent(tc.arguments)
                                )
                            }
                            return Transcript.ToolCall(
                                id: tc.id,
                                toolName: tc.name,
                                arguments: decodedContent
                            )
                        }
                        let toolCallsSegment = Transcript.ToolCallsSegment(calls: transcriptCalls)
                        let responseEntry = Transcript.Entry.response(
                            Transcript.Response(
                                assetIDs: [],
                                segments: [.toolCalls(toolCallsSegment)]
                            )
                        )
                        entries.append(responseEntry)
                    } else if let content = message.content {
                        // Regular text response
                        let responseEntry = Transcript.Entry.response(
                            Transcript.Response(
                                assetIDs: [],
                                segments: [.text(.init(content: content))]
                            )
                        )
                        entries.append(responseEntry)
                    }

                case .tool:
                    // Tool results are handled by AnyLanguageModel internally
                    // We store them for record-keeping but don't reconstruct them into transcript
                    break

                case .system:
                    // System messages are handled via instructions
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
        sessionId: UUID,
        with transcript: Transcript
    ) async -> LanguageModelSession {
        logger.debug("Creating language model session", metadata: ["agent.id": .string(agent.id), "model.name": .string(agent.modelName)])
        guard let model = models[agent.modelName] else {
            logger.error("Model not found", metadata: ["agent.id": .string(agent.id), "model.name": .string(agent.modelName)])
            fatalError("Model '\(agent.modelName)' not registered in AgentCenter")
        }

        let sessionTools = await tools(for: agent)
        logger.debug(
            "Language model session created", metadata: ["agent.id": .string(agent.id), "model.name": .string(agent.modelName), "tool.count": .stringConvertible(sessionTools.count)])

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

        // Create context for this agent run
        let context = RunContext(
            agentId: agent.id,
            sessionId: sessionId,
            emitEvent: { [weak self] event in
                guard let self = self else { return }
                Task { await self.emit(event) }
            }
        )

        // Set up event handler to use the context
        session.onEvent = { event in
            Task {
                await context.handleModelEvent(event)
            }
        }

        return session
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
                // Check for tool calls in response segments
                let toolCalls = extractToolCalls(from: response.segments)

                if !toolCalls.isEmpty {
                    // Assistant message with tool calls (no text content)
                    messages.append(.assistantWithTools(toolCalls))
                } else {
                    // Regular assistant message with text content
                    let content = extractTextContent(from: response.segments)
                    if !content.isEmpty {
                        messages.append(.assistant(content))
                    }
                }

            default:
                // Other entry types not yet supported
                break
            }
        }

        return messages
    }

    private func extractToolCalls(from segments: [Transcript.Segment]) -> [ToolCall] {
        var toolCalls: [ToolCall] = []

        for segment in segments {
            if case .toolCalls(let toolCallsSegment) = segment {
                for call in toolCallsSegment.calls {
                    // Convert GeneratedContent to String for storage
                    let argumentsString: String
                    if let data = try? JSONEncoder().encode(call.arguments),
                        let jsonString = String(data: data, encoding: .utf8)
                    {
                        argumentsString = jsonString
                    } else {
                        // Fallback: use string description
                        argumentsString = String(describing: call.arguments)
                    }

                    let toolCall = ToolCall(
                        id: call.id,
                        name: call.toolName,
                        arguments: argumentsString
                    )
                    toolCalls.append(toolCall)
                }
            }
        }

        return toolCalls
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

// MARK: - Hook Management

extension LiveAgentCenter {
    func register(preHook: RegisteredPreHook) async {
        logger.info("Registering pre-hook", metadata: ["hook.name": .string(preHook.config.name)])
        preHooks[preHook.config.name] = preHook
        logger.debug("Pre-hook registered successfully", metadata: ["hook.name": .string(preHook.config.name)])
    }

    func register(postHook: RegisteredPostHook) async {
        logger.info("Registering post-hook", metadata: ["hook.name": .string(postHook.config.name)])
        postHooks[postHook.config.name] = postHook
        logger.debug("Post-hook registered successfully", metadata: ["hook.name": .string(postHook.config.name)])
    }

    func preHook(named name: String) async -> RegisteredPreHook? {
        let hook = preHooks[name]
        if hook != nil {
            logger.debug("Pre-hook found", metadata: ["hook.name": .string(name)])
        } else {
            logger.warning("Pre-hook not found", metadata: ["hook.name": .string(name)])
        }
        return hook
    }

    func postHook(named name: String) async -> RegisteredPostHook? {
        let hook = postHooks[name]
        if hook != nil {
            logger.debug("Post-hook found", metadata: ["hook.name": .string(name)])
        } else {
            logger.warning("Post-hook not found", metadata: ["hook.name": .string(name)])
        }
        return hook
    }

    /// Execute a non-blocking hook in a background task
    private func executeNonBlockingHook<H: Sendable>(
        _ hook: H,
        hookName: String,
        execute: @Sendable @escaping (H) async throws -> Void
    ) {
        let taskId = UUID()
        let task = Task {
            do {
                try await execute(hook)
            } catch {
                logger.warning("Non-blocking hook failed", metadata: [
                    "hook.name": .string(hookName),
                    "error": .string(String(describing: error))
                ])
            }
            await self.removeBackgroundTask(taskId)
        }
        backgroundHookTasks[taskId] = task
    }

    private func removeBackgroundTask(_ id: UUID) {
        backgroundHookTasks.removeValue(forKey: id)
    }

    /// Wait for all background hooks to complete (for graceful shutdown)
    func waitForBackgroundHooks() async {
        logger.info("Waiting for background hooks", metadata: ["task.count": .stringConvertible(backgroundHookTasks.count)])
        await withTaskGroup(of: Void.self) { group in
            for task in backgroundHookTasks.values {
                group.addTask { await task.value }
            }
        }
        logger.info("All background hooks completed")
    }

    /// Cancel all background hooks
    func cancelBackgroundHooks() {
        logger.info("Cancelling background hooks", metadata: ["task.count": .stringConvertible(backgroundHookTasks.count)])
        for task in backgroundHookTasks.values {
            task.cancel()
        }
        backgroundHookTasks.removeAll()
        logger.info("All background hooks cancelled")
    }

    /// Execute pre-hooks for an agent
    /// - Parameters:
    ///   - agent: The agent to execute hooks for
    ///   - context: The hook context (mutable - blocking hooks can modify userMessage)
    private func executePreHooks(for agent: Agent, context: inout HookContext) async throws {
        let allPreHooks = agent.preHookNames.compactMap { preHooks[$0] }
        guard !allPreHooks.isEmpty else { return }

        let blockingHooks = allPreHooks.filter { $0.config.blocking }
        let nonBlockingHooks = allPreHooks.filter { !$0.config.blocking }

        logger.debug("Executing pre-hooks", metadata: [
            "blocking.count": .stringConvertible(blockingHooks.count),
            "non-blocking.count": .stringConvertible(nonBlockingHooks.count)
        ])

        // Execute blocking pre-hooks sequentially (can modify context)
        for hook in blockingHooks {
            logger.debug("Executing blocking pre-hook", metadata: ["hook.name": .string(hook.config.name)])
            try await hook.execute(&context)
        }

        // Launch non-blocking pre-hooks (get a copy, cannot modify)
        for hook in nonBlockingHooks {
            logger.debug("Launching non-blocking pre-hook", metadata: ["hook.name": .string(hook.config.name)])
            let contextCopy = context  // Non-blocking hooks get a copy
            executeNonBlockingHook(hook, hookName: hook.config.name) { hook in
                var mutableContext = contextCopy
                try await hook.execute(&mutableContext)
            }
        }
    }

    /// Execute post-hooks for an agent
    private func executePostHooks(for agent: Agent, context: HookContext, run: Run) async {
        let allPostHooks = agent.postHookNames.compactMap { postHooks[$0] }
        guard !allPostHooks.isEmpty else { return }

        let blockingHooks = allPostHooks.filter { $0.config.blocking }
        let nonBlockingHooks = allPostHooks.filter { !$0.config.blocking }

        logger.debug("Executing post-hooks", metadata: [
            "blocking.count": .stringConvertible(blockingHooks.count),
            "non-blocking.count": .stringConvertible(nonBlockingHooks.count)
        ])

        // Execute blocking post-hooks sequentially
        for hook in blockingHooks {
            logger.debug("Executing blocking post-hook", metadata: ["hook.name": .string(hook.config.name)])
            do {
                try await hook.execute(context, run)
            } catch {
                // Log error but don't propagate - post-hooks shouldn't fail the run
                logger.warning("Blocking post-hook failed", metadata: [
                    "hook.name": .string(hook.config.name),
                    "error": .string(String(describing: error))
                ])
            }
        }

        // Launch non-blocking post-hooks
        for hook in nonBlockingHooks {
            logger.debug("Launching non-blocking post-hook", metadata: ["hook.name": .string(hook.config.name)])
            executeNonBlockingHook(hook, hookName: hook.config.name) { hook in
                try await hook.execute(context, run)
            }
        }
    }
}
