import AnyLanguageModel
import Dependencies
import Foundation

struct AgentSessionContext: Sendable, Codable, Hashable {
    let agent: Agent
    let userId: UUID
    let sessionId: UUID
}

/// The core agent that orchestrates model interactions and storage
public struct Agent: Sendable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let description: String

    public var sessionId: UUID
    public var userId: UUID

    package let modelName: String
    package var toolNames: [String]
    package let mcpServerNames: [String]
    package let instructions: String?

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        sessionId: UUID = UUID(),
        userId: UUID = UUID(),
        modelName: String,
        instructions: String? = nil,
        toolNames: [String] = [],
        mcpServerNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sessionId = sessionId
        self.userId = userId
        self.modelName = modelName
        self.toolNames = toolNames
        self.instructions = instructions
        self.mcpServerNames = mcpServerNames
    }
}

// MARK: - Agent Execution

extension Agent {
    /// Run the agent with a user message
    /// - Parameters:
    ///   - message: The user's input message
    ///   - loadHistory: Whether to load previous runs for context (default: true)
    /// - Returns: The run result containing all messages and the final response
    public func run<T: Codable & Generable>(
        message: String,
        as type: T.Type,
        loadHistory: Bool = true
    ) async throws -> Run {
        // Load transcript with history
        let transcript = try await loadTranscript(includeHistory: loadHistory)

        // Create session with conversation history
        let session = await createSession(with: transcript)

        // Use AnyLanguageModel's session to handle the conversation
        let response = try await session.respond(to: message, generating: T.self)
        let content: Data?

        if let string = response.content as? String {
            // Extract content from response
            content = string.data(using: .utf8)
        } else {
            content = try JSONEncoder().encode(response.content)
        }

        // Create messages from the session transcript
        let messages = extractMessages(from: session.transcript)

        // Create run record
        let run = Run(
            agentId: id,
            sessionId: sessionId,
            userId: userId,
            messages: messages,
            rawContent: content,
        )

        // Save to storage
        @Dependency(\.storage) var storage
        try await storage.append(run, for: self)

        return run
    }

    /// Stream responses from the agent
    /// - Parameters:
    ///   - message: The user's input message
    ///   - loadHistory: Whether to load previous runs for context (default: true)
    /// - Returns: An async stream of response chunks
    public func stream(
        message: String,
        loadHistory: Bool = true
    ) -> AsyncThrowingStream<String, Error> {
        .init { continuation in
            let task = Task {
                do {
                    // Load transcript with history
                    let transcript = try await loadTranscript(includeHistory: loadHistory)

                    // Create session with history
                    let session = await createSession(with: transcript)

                    // Use respond() which handles tool calls automatically
                    let response = try await session.respond { Prompt(message) }

                    // The response content is already a String
                    continuation.yield(String(describing: response.content))

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

// MARK: - Transcript Management

extension Agent {
    fileprivate func tools() async -> [any Tool] {
        @Dependency(\.agentCenter) var agentCenter
        var result: [any Tool] = []
        for toolName in toolNames {
            if let tool = await agentCenter.tool(named: toolName) {
                result.append(tool)
            }
        }
        return result
    }

    fileprivate func model() async -> any LanguageModel {
        @Dependency(\.agentCenter) var agentCenter
        guard let model = await agentCenter.model(named: modelName) else {
            fatalError("Model '\(modelName)' not registered in AgentCenter")
        }
        return model
    }

    /// Load transcript with optional history
    fileprivate func loadTranscript(includeHistory: Bool) async throws -> Transcript {
        @Dependency(\.storage) var storage
        let previousRuns = includeHistory ? try await storage.runs(for: self) : []
        return try await buildTranscript(from: previousRuns)
    }

    /// Build a Transcript from previous runs
    fileprivate func buildTranscript(from runs: [Run]) async throws -> Transcript {
        var entries: [Transcript.Entry] = []

        // Add instructions if available
        if let instructions = instructions {
            let toolDefs = await tools().map { Transcript.ToolDefinition(tool: $0) }
            let instructionsEntry = Transcript.Entry.instructions(
                Transcript.Instructions(
                    segments: [.text(.init(content: instructions))],
                    toolDefinitions: toolDefs
                )
            )
            entries.append(instructionsEntry)
        }

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

        return Transcript(entries: entries)
    }

    /// Extract messages from a Transcript for storage
    fileprivate func extractMessages(from transcript: Transcript) -> [Message] {
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

    /// Extract text content from transcript segments
    fileprivate func extractTextContent(from segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined(separator: "\n")
    }
}

// MARK: - Session Management

extension Agent {
    /// Create a language model session with transcript
    fileprivate func createSession(with transcript: Transcript) async -> LanguageModelSession {
        LanguageModelSession(
            model: await model(),
            tools: await tools(),
            transcript: transcript
        )
    }
}

// MARK: - Agent Errors

public enum AgentError: Error, CustomStringConvertible {
    case noResponseFromModel
    case invalidConfiguration(String)
    case invalidJSONResponse

    public var description: String {
        switch self {
        case .noResponseFromModel:
            return "No response received from model"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .invalidJSONResponse:
            return "Could not parse JSON from model response"
        }
    }
}
