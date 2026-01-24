import Foundation

/// Represents the result of an agent execution
public struct Run: Sendable, Codable, Identifiable {
    public let id: UUID
    public let agentId: UUID
    public let sessionId: UUID
    public let userId: UUID
    public let messages: [Message]
    public let rawContent: Data?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        agentId: UUID,
        sessionId: UUID,
        userId: UUID,
        messages: [Message],
        rawContent: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.sessionId = sessionId
        self.userId = userId
        self.messages = messages
        self.rawContent = rawContent
        self.createdAt = createdAt
    }
}

// MARK: - Structured Content Helper

extension Run {
    /// Decode structured content from the run
    /// - Parameter type: The type to decode to
    /// - Returns: The decoded structured content
    /// - Throws: DecodingError if the structured data cannot be decoded
    public func decoded<T: Decodable>(as type: T.Type) throws -> T {
        guard let data = rawContent else {
            throw RunError.noData
        }

        return try JSONDecoder().decode(type, from: data)
    }

    public func asString() throws -> String {
        guard let data = rawContent else {
            throw RunError.noData
        }

        return String(data: data, encoding: .utf8)!
    }
}

public enum RunError: Error {
    case noData
}
