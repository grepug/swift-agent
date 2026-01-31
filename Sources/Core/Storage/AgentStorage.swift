import Dependencies
import Foundation

/// Options for sorting sessions
public enum SessionSortOption: String, Sendable {
    case createdAtAsc
    case createdAtDesc
    case updatedAtAsc
    case updatedAtDesc
    case nameAsc
    case nameDesc
}

/// Storage statistics
public struct StorageStats: Sendable, Codable {
    public let totalSessions: Int
    public let totalRuns: Int
    public let totalMessages: Int
    public let oldestSession: Date?
    public let newestSession: Date?

    public init(
        totalSessions: Int,
        totalRuns: Int,
        totalMessages: Int,
        oldestSession: Date?,
        newestSession: Date?
    ) {
        self.totalSessions = totalSessions
        self.totalRuns = totalRuns
        self.totalMessages = totalMessages
        self.oldestSession = oldestSession
        self.newestSession = newestSession
    }
}

/// Protocol for storing agent sessions, runs, and state
public protocol AgentStorage: Sendable {
    // MARK: - Session Management

    /// Get a specific session
    func getSession(
        sessionId: UUID,
        agentId: String?,
        userId: UUID?
    ) async throws -> AgentSession?

    /// Get multiple sessions with filtering
    func getSessions(
        agentId: String?,
        userId: UUID?,
        limit: Int?,
        offset: Int?,
        sortBy: SessionSortOption?
    ) async throws -> [AgentSession]

    /// Create or update a session
    func upsertSession(_ session: AgentSession) async throws -> AgentSession

    /// Delete a session
    func deleteSession(sessionId: UUID) async throws -> Bool

    /// Rename a session
    func renameSession(sessionId: UUID, name: String) async throws -> AgentSession?

    // MARK: - Run Management

    /// Get a specific run
    func getRun(runId: UUID, sessionId: UUID) async throws -> Run?

    /// Append run to session (also updates session.updatedAt)
    func appendRun(_ run: Run, sessionId: UUID) async throws

    /// Remove a run
    func removeRun(runId: UUID, sessionId: UUID) async throws

    // MARK: - Utilities

    /// Get storage statistics
    func getStats() async throws -> StorageStats
}

extension DependencyValues {
    public var storage: AgentStorage {
        get { self[StorageKey.self] }
        set { self[StorageKey.self] = newValue }
    }

    private enum StorageKey: DependencyKey {
        static let liveValue: AgentStorage = FileAgentStorage()
        static let testValue: AgentStorage = FileAgentStorage()
    }
}
