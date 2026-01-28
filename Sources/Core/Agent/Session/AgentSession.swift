import Foundation

/// Represents a complete agent session with conversation history and state
public struct AgentSession: Sendable, Codable, Identifiable {
    public let id: UUID
    public let agentId: String
    public let userId: UUID
    public var name: String?

    // Message history (conversation memory)
    public var messages: [Message]

    // Run history
    public var runs: [Run]

    // Custom session data (persists across runs)
    public var sessionData: [String: AnyCodable]

    // Optional summary for long conversations
    public var summary: String?

    // Metadata
    public let createdAt: Date
    public var updatedAt: Date

    // Additional metadata
    public var metadata: [String: AnyCodable]

    public init(
        id: UUID = UUID(),
        agentId: String,
        userId: UUID,
        name: String? = nil,
        messages: [Message] = [],
        runs: [Run] = [],
        sessionData: [String: AnyCodable] = [:],
        summary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.agentId = agentId
        self.userId = userId
        self.name = name
        self.messages = messages
        self.runs = runs
        self.sessionData = sessionData
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

// MARK: - Convenience Methods

extension AgentSession {
    /// Get a specific run by ID
    public func getRun(id: UUID) -> Run? {
        runs.first { $0.id == id }
    }

    /// Get the most recent run
    public var latestRun: Run? {
        runs.max(by: { $0.createdAt < $1.createdAt })
    }

    /// Total number of runs in this session
    public var runCount: Int {
        runs.count
    }

    /// Total number of messages in this session
    public var messageCount: Int {
        messages.count
    }
}
