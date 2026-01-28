import Foundation

/// In-memory implementation of storage (for development/testing)
public actor InMemoryAgentStorage: AgentStorage {
    private var sessions: [UUID: AgentSession] = [:]

    public init() {}

    // MARK: - Session Management

    public func getSession(
        sessionId: UUID,
        agentId: String? = nil,
        userId: UUID? = nil
    ) async throws -> AgentSession? {
        guard let session = sessions[sessionId] else { return nil }

        // Apply filters if provided
        if let agentId = agentId, session.agentId != agentId { return nil }
        if let userId = userId, session.userId != userId { return nil }

        return session
    }

    public func getSessions(
        agentId: String? = nil,
        userId: UUID? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        sortBy: SessionSortOption? = nil
    ) async throws -> [AgentSession] {
        var filtered = Array(sessions.values)

        // Apply filters
        if let agentId = agentId {
            filtered = filtered.filter { $0.agentId == agentId }
        }
        if let userId = userId {
            filtered = filtered.filter { $0.userId == userId }
        }

        // Sort
        filtered = sortSessions(filtered, by: sortBy ?? .updatedAtDesc)

        // Paginate
        let startIndex = offset ?? 0
        let endIndex = limit.map { min(startIndex + $0, filtered.count) } ?? filtered.count

        guard startIndex < filtered.count else { return [] }
        return Array(filtered[startIndex..<endIndex])
    }

    public func upsertSession(_ session: AgentSession) async throws -> AgentSession {
        var updatedSession = session
        updatedSession.updatedAt = Date()
        sessions[session.id] = updatedSession
        return updatedSession
    }

    public func deleteSession(sessionId: UUID) async throws -> Bool {
        guard sessions[sessionId] != nil else { return false }
        sessions.removeValue(forKey: sessionId)
        return true
    }

    public func renameSession(sessionId: UUID, name: String) async throws -> AgentSession? {
        guard var session = sessions[sessionId] else { return nil }
        session.name = name
        session.updatedAt = Date()
        sessions[sessionId] = session
        return session
    }

    // MARK: - Run Management

    public func getRun(runId: UUID, sessionId: UUID) async throws -> Run? {
        guard let session = sessions[sessionId] else { return nil }
        return session.runs.first { $0.id == runId }
    }

    public func appendRun(_ run: Run, sessionId: UUID) async throws {
        guard var session = sessions[sessionId] else {
            throw StorageError.sessionNotFound(sessionId)
        }

        session.runs.append(run)
        session.updatedAt = Date()
        sessions[sessionId] = session
    }

    public func removeRun(runId: UUID, sessionId: UUID) async throws {
        guard var session = sessions[sessionId] else {
            throw StorageError.sessionNotFound(sessionId)
        }

        session.runs.removeAll { $0.id == runId }
        session.updatedAt = Date()
        sessions[sessionId] = session
    }

    // MARK: - Message Management

    public func appendMessages(_ messages: [Message], sessionId: UUID) async throws {
        guard var session = sessions[sessionId] else {
            throw StorageError.sessionNotFound(sessionId)
        }

        session.messages.append(contentsOf: messages)
        session.updatedAt = Date()
        sessions[sessionId] = session
    }

    public func getMessages(sessionId: UUID, limit: Int? = nil) async throws -> [Message] {
        guard let session = sessions[sessionId] else { return [] }

        if let limit = limit {
            return Array(session.messages.suffix(limit))
        }
        return session.messages
    }

    public func clearMessages(sessionId: UUID, olderThan: Date) async throws {
        guard var session = sessions[sessionId] else {
            throw StorageError.sessionNotFound(sessionId)
        }

        session.messages.removeAll { $0.createdAt < olderThan }
        session.updatedAt = Date()
        sessions[sessionId] = session
    }

    // MARK: - Session Data Management

    public func updateSessionData(
        _ data: [String: AnyCodable],
        sessionId: UUID,
        merge: Bool = true
    ) async throws {
        guard var session = sessions[sessionId] else {
            throw StorageError.sessionNotFound(sessionId)
        }

        if merge {
            session.sessionData.merge(data) { _, new in new }
        } else {
            session.sessionData = data
        }

        session.updatedAt = Date()
        sessions[sessionId] = session
    }

    public func getSessionData(sessionId: UUID) async throws -> [String: AnyCodable]? {
        return sessions[sessionId]?.sessionData
    }

    // MARK: - Utilities

    public func getStats() async throws -> StorageStats {
        let allSessions = Array(sessions.values)

        let totalSessions = allSessions.count
        let totalRuns = allSessions.reduce(0) { $0 + $1.runs.count }
        let totalMessages = allSessions.reduce(0) { $0 + $1.messages.count }
        let oldestSession = allSessions.map(\.createdAt).min()
        let newestSession = allSessions.map(\.updatedAt).max()

        return StorageStats(
            totalSessions: totalSessions,
            totalRuns: totalRuns,
            totalMessages: totalMessages,
            oldestSession: oldestSession,
            newestSession: newestSession
        )
    }

    // MARK: - Private Helpers

    private func sortSessions(_ sessions: [AgentSession], by option: SessionSortOption) -> [AgentSession] {
        switch option {
        case .createdAtAsc:
            return sessions.sorted { $0.createdAt < $1.createdAt }
        case .createdAtDesc:
            return sessions.sorted { $0.createdAt > $1.createdAt }
        case .updatedAtAsc:
            return sessions.sorted { $0.updatedAt < $1.updatedAt }
        case .updatedAtDesc:
            return sessions.sorted { $0.updatedAt > $1.updatedAt }
        case .nameAsc:
            return sessions.sorted { ($0.name ?? "") < ($1.name ?? "") }
        case .nameDesc:
            return sessions.sorted { ($0.name ?? "") > ($1.name ?? "") }
        }
    }
}
