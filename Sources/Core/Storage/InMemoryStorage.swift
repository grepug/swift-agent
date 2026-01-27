import Foundation

/// In-memory implementation of storage (for development/testing)
public actor InMemoryStorage: StorageProtocol {
    private var runsStorage: [String: [Run]] = [:]
    private var sessionStateStorage: [String: [UUID: AnyCodable]] = [:]

    public init() {}

    public func runs(for agent: Agent) async throws -> [Run] {
        return runsStorage[agent.id] ?? []
    }

    public func removeRun(id: UUID, sessionId: UUID) async throws {
        // Need to find which agent this run belongs to
        for (agentId, runs) in runsStorage {
            if runs.contains(where: { $0.id == id }) {
                runsStorage[agentId]?.removeAll(where: { $0.id == id })
                return
            }
        }
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
