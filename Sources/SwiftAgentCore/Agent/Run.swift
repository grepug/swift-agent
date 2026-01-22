import Foundation

/// Represents the result of an agent execution
public struct Run: Sendable, Codable, Identifiable {
    public let id: UUID
    public let agentId: UUID
    public let sessionId: UUID
    public let userId: UUID
    public let messages: [Message]
    public let content: String?
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        agentId: UUID,
        sessionId: UUID,
        userId: UUID,
        messages: [Message],
        content: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.sessionId = sessionId
        self.userId = userId
        self.messages = messages
        self.content = content
        self.createdAt = createdAt
    }
}
