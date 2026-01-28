import Dependencies
import Foundation

/// Protocol for storing agent runs and session state
public protocol AgentStorage: Sendable {
    /// Retrieve all runs for an agent
    func runs(for agent: Agent) async throws -> [Run]

    func removeRun(id: UUID, sessionId: UUID) async throws

    /// Append a new run for an agent
    func append(_ run: Run, for agent: Agent) async throws

    /// Get session state for an agent
    func sessionState(for agent: Agent, sessionId: UUID) async throws -> AnyCodable?

    /// Update session state for an agent
    func updateSessionState(_ state: AnyCodable, for agent: Agent, sessionId: UUID) async throws
}

extension DependencyValues {
    public var storage: AgentStorage {
        get { self[StorageKey.self] }
        set { self[StorageKey.self] = newValue }
    }

    private enum StorageKey: DependencyKey {
        static let liveValue: AgentStorage = InMemoryAgentStorage()
        static let testValue: AgentStorage = InMemoryAgentStorage()
    }
}
