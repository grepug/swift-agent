import AnyLanguageModel
import Foundation

/// The core agent that orchestrates model interactions and storage
public struct Agent: Sendable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let sessionId: UUID
    public let userId: UUID

    private let model: any LanguageModel
    private let tools: [any Tool]
    private let instructions: String?
    private let storage: StorageProtocol

    public init(
        id: UUID = UUID(),
        name: String = "Default Agent",
        description: String? = nil,
        sessionId: UUID = UUID(),
        userId: UUID = UUID(),
        model: any LanguageModel,
        storage: StorageProtocol = InMemoryStorage(),
        instructions: String? = nil,
        tools: [any Tool] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sessionId = sessionId
        self.userId = userId
        self.model = model
        self.tools = tools
        self.instructions = instructions
        self.storage = storage
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
        // Load previous runs to build transcript
        let previousRuns = loadHistory ? try await storage.runs(for: self) : []

        // Build transcript from history
        let transcript = try buildTranscript(from: previousRuns)

        // Create session with conversation history
        let session = LanguageModelSession(
            model: model,
            tools: tools,
            transcript: transcript
        )

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
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Load previous runs to build transcript
                    let previousRuns = loadHistory ? try await storage.runs(for: self) : []
                    let transcript = try buildTranscript(from: previousRuns)

                    // Create session with history
                    let session = LanguageModelSession(
                        model: model,
                        tools: tools,
                        transcript: transcript
                    )

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

    /// Build a Transcript from previous runs
    private func buildTranscript(from runs: [Run]) throws -> Transcript {
        var entries: [Transcript.Entry] = []

        // Add instructions if available
        if let instructions = instructions {
            let toolDefs = tools.map { Transcript.ToolDefinition(tool: $0) }
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
    private func extractMessages(from transcript: Transcript) -> [Message] {
        var messages: [Message] = []

        for entry in transcript {
            switch entry {
            case .instructions(let inst):
                // Store as system message
                let content = inst.segments.compactMap { segment in
                    if case .text(let text) = segment {
                        return text.content
                    }
                    return nil
                }.joined(separator: "\n")

                if !content.isEmpty {
                    messages.append(.system(content))
                }

            case .prompt(let prompt):
                let content = prompt.segments.compactMap { segment in
                    if case .text(let text) = segment {
                        return text.content
                    }
                    return nil
                }.joined(separator: "\n")

                if !content.isEmpty {
                    messages.append(.user(content))
                }

            case .response(let response):
                let content = response.segments.compactMap { segment in
                    if case .text(let text) = segment {
                        return text.content
                    }
                    return nil
                }.joined(separator: "\n")

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
