import Foundation

/// Represents a conversation session
public struct Session: Sendable, Identifiable {
    public let id: UUID
    public let userId: UUID
    public let createdAt: Date
    public let name: String?

    public init(
        id: UUID = UUID(),
        userId: UUID,
        createdAt: Date = Date(),
        name: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.createdAt = createdAt
        self.name = name
    }
}
