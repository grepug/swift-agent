import Foundation

/// Run execution status
public enum RunStatus: String, Sendable, Codable {
    case running
    case completed
    case failed
    case cancelled
    case paused
}

/// Metrics for a run execution
public struct RunMetrics: Sendable, Codable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let durationMs: Int?
    public let cost: Decimal?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        durationMs: Int? = nil,
        cost: Decimal? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.durationMs = durationMs
        self.cost = cost
    }
}

/// Tool execution record
public struct ToolExecution: Sendable, Codable, Identifiable {
    public let id: UUID
    public let toolName: String
    public let arguments: AnyCodable
    public let result: AnyCodable?
    public let error: String?
    public let durationMs: Int?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        toolName: String,
        arguments: AnyCodable,
        result: AnyCodable? = nil,
        error: String? = nil,
        durationMs: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.error = error
        self.durationMs = durationMs
        self.timestamp = timestamp
    }
}

/// Represents the result of an agent execution
public struct Run: Sendable, Codable, Identifiable {
    public let id: UUID
    public let agentId: String
    public let sessionId: UUID
    public let userId: UUID
    public let parentRunId: UUID?

    // Content
    public let messages: [Message]
    public let rawContent: Data?

    // Metadata
    public let createdAt: Date
    public var status: RunStatus

    // Model information
    public let modelName: String?
    public let modelProvider: String?

    // Execution tracking
    public var toolExecutions: [ToolExecution]

    // Metrics
    public var metrics: RunMetrics?

    // Session state updates made during this run
    public var sessionDataUpdates: [String: AnyCodable]?

    // Additional metadata
    public var metadata: [String: AnyCodable]

    public init(
        id: UUID = UUID(),
        agentId: String,
        sessionId: UUID,
        userId: UUID,
        parentRunId: UUID? = nil,
        messages: [Message],
        rawContent: Data? = nil,
        createdAt: Date = Date(),
        status: RunStatus = .completed,
        modelName: String? = nil,
        modelProvider: String? = nil,
        toolExecutions: [ToolExecution] = [],
        metrics: RunMetrics? = nil,
        sessionDataUpdates: [String: AnyCodable]? = nil,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.agentId = agentId
        self.sessionId = sessionId
        self.userId = userId
        self.parentRunId = parentRunId
        self.messages = messages
        self.rawContent = rawContent
        self.createdAt = createdAt
        self.status = status
        self.modelName = modelName
        self.modelProvider = modelProvider
        self.toolExecutions = toolExecutions
        self.metrics = metrics
        self.sessionDataUpdates = sessionDataUpdates
        self.metadata = metadata
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

        guard let text = String(data: data, encoding: .utf8) else {
            throw RunError.invalidUTF8Data
        }
        return text
    }
}

public enum RunError: Error {
    case noData
    case invalidUTF8Data
}
