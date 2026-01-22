import Foundation

/// Protocol for storing agent runs and session state
public protocol StorageProtocol: Sendable {
    /// Retrieve all runs for an agent
    func runs(for agent: Agent) async throws -> [Run]
    
    /// Append a new run for an agent
    func append(_ run: Run, for agent: Agent) async throws

    /// Get session state for an agent
    func sessionState(for agent: Agent, sessionId: UUID) async throws -> AnyCodable?
    
    /// Update session state for an agent
    func updateSessionState(_ state: AnyCodable, for agent: Agent, sessionId: UUID) async throws
}

/// In-memory implementation of storage (for development/testing)
public actor InMemoryStorage: StorageProtocol {
    private var runsStorage: [UUID: [Run]] = [:]
    private var sessionStateStorage: [UUID: [UUID: AnyCodable]] = [:]

    public init() {}

    public func runs(for agent: Agent) async throws -> [Run] {
        return runsStorage[agent.id] ?? []
    }

    public func append(_ run: Run, for agent: Agent) async throws {
        runsStorage[agent.id, default: []].append(run)
    }

    public func sessionState(for agent: Agent, sessionId: UUID) async throws -> AnyCodable? {
        return sessionStateStorage[agent.id]?[sessionId]
    }

    public func updateSessionState(_ state: AnyCodable, for agent: Agent, sessionId: UUID) async throws {
        sessionStateStorage[agent.id, default: [:]][sessionId] = state
    }
}
