import Foundation

/// Represents a session context for executing an agent
public struct AgentSessionContext: Sendable, Codable, Hashable {
    public let agentId: String
    public let userId: UUID
    public let sessionId: UUID

    public init(
        agentId: String,
        userId: UUID,
        sessionId: UUID = UUID()
    ) {
        self.agentId = agentId
        self.userId = userId
        self.sessionId = sessionId
    }
}
