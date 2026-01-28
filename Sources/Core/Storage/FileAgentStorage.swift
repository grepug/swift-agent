import Foundation

/// File-based implementation of AgentStorage for debug/development purposes
/// Uses human-readable JSON files with sortable names for easy browsing
public actor FileAgentStorage: AgentStorage {
    private let rootURL: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootPath: String? = nil) {
        // Determine root directory
        if let path = rootPath {
            self.rootURL = URL(fileURLWithPath: path)
        } else if let envPath = ProcessInfo.processInfo.environment["SWIFT_AGENT_STORAGE_DIR"] {
            self.rootURL = URL(fileURLWithPath: envPath)
        } else {
            // Default to .data directory in current working directory
            self.rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".data")
        }

        // Configure encoder for human-readable output
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        // Configure decoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        // Create root directory
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    // MARK: - Session Management

    public func getSession(
        sessionId: UUID,
        agentId: String? = nil,
        userId: UUID? = nil
    ) async throws -> AgentSession? {
        // If agentId is provided, look in specific agent directory
        if let agentId = agentId {
            let sessionFile = try findSessionFile(sessionId: sessionId, agentId: agentId)
            guard let sessionFile = sessionFile else { return nil }
            return try loadSession(from: sessionFile)
        }

        // Otherwise, scan all agent directories
        let agentsDir = rootURL.appendingPathComponent("agents")
        guard fileManager.fileExists(atPath: agentsDir.path) else { return nil }

        let agentDirs = try fileManager.contentsOfDirectory(
            at: agentsDir,
            includingPropertiesForKeys: nil
        )

        for agentDir in agentDirs {
            if let sessionFile = try findSessionFile(sessionId: sessionId, agentId: agentDir.lastPathComponent) {
                return try loadSession(from: sessionFile)
            }
        }

        return nil
    }

    public func getSessions(
        agentId: String?,
        userId: UUID?,
        limit: Int? = nil,
        offset: Int? = nil,
        sortBy: SessionSortOption? = nil
    ) async throws -> [AgentSession] {
        var allSessions: [AgentSession] = []

        let agentsDir = rootURL.appendingPathComponent("agents")
        guard fileManager.fileExists(atPath: agentsDir.path) else { return [] }

        // Determine which agent directories to scan
        let agentDirs: [URL]
        if let agentId = agentId {
            let specificAgentDir = agentsDir.appendingPathComponent(sanitizeAgentId(agentId))
            agentDirs = fileManager.fileExists(atPath: specificAgentDir.path) ? [specificAgentDir] : []
        } else {
            agentDirs = try fileManager.contentsOfDirectory(
                at: agentsDir,
                includingPropertiesForKeys: nil
            ).filter { $0.hasDirectoryPath }
        }

        // Load all sessions
        for agentDir in agentDirs {
            let sessionsDir = agentDir.appendingPathComponent("sessions")
            guard fileManager.fileExists(atPath: sessionsDir.path) else { continue }

            let sessionDirs = try fileManager.contentsOfDirectory(
                at: sessionsDir,
                includingPropertiesForKeys: nil
            ).filter { $0.hasDirectoryPath }

            for sessionDir in sessionDirs {
                let sessionFile = sessionDir.appendingPathComponent("session.json")
                if let session = try? loadSession(from: sessionFile) {
                    // Filter by userId if specified
                    if let userId = userId, session.userId != userId {
                        continue
                    }
                    allSessions.append(session)
                }
            }
        }

        // Sort sessions
        let sortedSessions = sortSessions(allSessions, by: sortBy ?? .updatedAtDesc)

        // Apply pagination
        let startIndex = offset ?? 0
        let endIndex = limit.map { min(startIndex + $0, sortedSessions.count) } ?? sortedSessions.count

        guard startIndex < sortedSessions.count else { return [] }
        return Array(sortedSessions[startIndex..<endIndex])
    }

    public func upsertSession(_ session: AgentSession) async throws -> AgentSession {
        var updatedSession = session
        updatedSession.updatedAt = Date()

        let sessionDir = sessionDirectory(agentId: session.agentId, sessionId: session.id)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let sessionFile = sessionDir.appendingPathComponent("session.json")
        let data = try encoder.encode(updatedSession)
        try data.write(to: sessionFile, options: .atomic)

        logVerbose("Upserted session: \(session.id)")
        return updatedSession
    }

    public func deleteSession(sessionId: UUID) async throws -> Bool {
        // Find and delete session directory
        let agentsDir = rootURL.appendingPathComponent("agents")
        guard fileManager.fileExists(atPath: agentsDir.path) else { return false }

        let agentDirs = try fileManager.contentsOfDirectory(
            at: agentsDir,
            includingPropertiesForKeys: nil
        )

        for agentDir in agentDirs {
            let sessionsDir = agentDir.appendingPathComponent("sessions")
            guard fileManager.fileExists(atPath: sessionsDir.path) else { continue }

            let sessionDirs = try fileManager.contentsOfDirectory(
                at: sessionsDir,
                includingPropertiesForKeys: nil
            ).filter { $0.hasDirectoryPath }

            for sessionDir in sessionDirs {
                let sessionFile = sessionDir.appendingPathComponent("session.json")
                if let session = try? loadSession(from: sessionFile), session.id == sessionId {
                    try fileManager.removeItem(at: sessionDir)
                    logVerbose("Deleted session: \(sessionId)")
                    return true
                }
            }
        }

        return false
    }

    public func renameSession(sessionId: UUID, name: String) async throws -> AgentSession? {
        guard var session = try await getSession(sessionId: sessionId) else { return nil }
        session.name = name
        return try await upsertSession(session)
    }

    // MARK: - Run Management

    public func getRun(runId: UUID, sessionId: UUID) async throws -> Run? {
        guard let session = try await getSession(sessionId: sessionId) else { return nil }
        return session.runs.first { $0.id == runId }
    }

    public func appendRun(_ run: Run, sessionId: UUID) async throws {
        guard var session = try await getSession(sessionId: sessionId) else {
            throw StorageError.sessionNotFound(sessionId)
        }

        session.runs.append(run)
        _ = try await upsertSession(session)

        logVerbose("Appended run \(run.id) to session \(sessionId)")
    }

    public func removeRun(runId: UUID, sessionId: UUID) async throws {
        guard var session = try await getSession(sessionId: sessionId) else {
            throw StorageError.sessionNotFound(sessionId)
        }

        session.runs.removeAll { $0.id == runId }
        _ = try await upsertSession(session)

        logVerbose("Removed run \(runId) from session \(sessionId)")
    }

    // MARK: - Message Management

    public func appendMessages(_ messages: [Message], sessionId: UUID) async throws {
        guard var session = try await getSession(sessionId: sessionId) else {
            throw StorageError.sessionNotFound(sessionId)
        }

        session.messages.append(contentsOf: messages)
        _ = try await upsertSession(session)

        logVerbose("Appended \(messages.count) messages to session \(sessionId)")
    }

    public func getMessages(sessionId: UUID, limit: Int? = nil) async throws -> [Message] {
        guard let session = try await getSession(sessionId: sessionId) else { return [] }

        if let limit = limit {
            return Array(session.messages.suffix(limit))
        }
        return session.messages
    }

    public func clearMessages(sessionId: UUID, olderThan: Date) async throws {
        guard var session = try await getSession(sessionId: sessionId) else {
            throw StorageError.sessionNotFound(sessionId)
        }

        let originalCount = session.messages.count
        session.messages.removeAll { $0.createdAt < olderThan }

        if session.messages.count != originalCount {
            _ = try await upsertSession(session)
            logVerbose("Cleared \(originalCount - session.messages.count) messages from session \(sessionId)")
        }
    }

    // MARK: - Session Data Management

    public func updateSessionData(
        _ data: [String: AnyCodable],
        sessionId: UUID,
        merge: Bool = true
    ) async throws {
        guard var session = try await getSession(sessionId: sessionId) else {
            throw StorageError.sessionNotFound(sessionId)
        }

        if merge {
            session.sessionData.merge(data) { _, new in new }
        } else {
            session.sessionData = data
        }

        _ = try await upsertSession(session)
        logVerbose("Updated session data for session \(sessionId)")
    }

    public func getSessionData(sessionId: UUID) async throws -> [String: AnyCodable]? {
        guard let session = try await getSession(sessionId: sessionId) else { return nil }
        return session.sessionData
    }

    // MARK: - Utilities

    public func getStats() async throws -> StorageStats {
        var totalSessions = 0
        var totalRuns = 0
        var totalMessages = 0
        var oldestDate: Date?
        var newestDate: Date?

        let sessions = try await getSessions(agentId: nil, userId: nil)
        totalSessions = sessions.count

        for session in sessions {
            totalRuns += session.runs.count
            totalMessages += session.messages.count

            if let oldest = oldestDate {
                oldestDate = min(oldest, session.createdAt)
            } else {
                oldestDate = session.createdAt
            }

            if let newest = newestDate {
                newestDate = max(newest, session.updatedAt)
            } else {
                newestDate = session.updatedAt
            }
        }

        return StorageStats(
            totalSessions: totalSessions,
            totalRuns: totalRuns,
            totalMessages: totalMessages,
            oldestSession: oldestDate,
            newestSession: newestDate
        )
    }

    // MARK: - Private Helpers

    /// Get session directory with sortable naming
    /// Format: agents/{agent-id}/sessions/{yyyyMMddHHmmss}-{session-name-or-uuid}/
    private func sessionDirectory(agentId: String, sessionId: UUID) -> URL {
        let agentsDir = rootURL.appendingPathComponent("agents")
        let agentDir = agentsDir.appendingPathComponent(sanitizeAgentId(agentId))
        let sessionsDir = agentDir.appendingPathComponent("sessions")

        // Try to find existing session directory
        if let existingDir = try? findSessionDir(sessionId: sessionId, agentId: agentId) {
            return existingDir
        }

        // Create new session directory with sortable name
        let timestamp = formatTimestamp(Date())
        let uuidPrefix = String(sessionId.uuidString.prefix(6).lowercased())
        let dirName = "\(timestamp)-\(uuidPrefix)"

        return sessionsDir.appendingPathComponent(dirName)
    }

    private func findSessionDir(sessionId: UUID, agentId: String) throws -> URL? {
        let sessionsDir =
            rootURL
            .appendingPathComponent("agents")
            .appendingPathComponent(sanitizeAgentId(agentId))
            .appendingPathComponent("sessions")

        guard fileManager.fileExists(atPath: sessionsDir.path) else { return nil }

        let sessionDirs = try fileManager.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ).filter { $0.hasDirectoryPath }

        for dir in sessionDirs {
            let sessionFile = dir.appendingPathComponent("session.json")
            if let session = try? loadSession(from: sessionFile), session.id == sessionId {
                return dir
            }
        }

        return nil
    }

    private func findSessionFile(sessionId: UUID, agentId: String) throws -> URL? {
        guard let sessionDir = try findSessionDir(sessionId: sessionId, agentId: agentId) else {
            return nil
        }
        return sessionDir.appendingPathComponent("session.json")
    }

    private func loadSession(from file: URL) throws -> AgentSession {
        let data = try Data(contentsOf: file)
        return try decoder.decode(AgentSession.self, from: data)
    }

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

    private func sanitizeAgentId(_ agentId: String) -> String {
        agentId.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// Format timestamp as yyyyMMddHHmmss for sortable filenames
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func logVerbose(_ message: String) {
        if ProcessInfo.processInfo.environment["SWIFT_AGENT_STORAGE_VERBOSE"] != nil {
            print("[FileAgentStorage] \(message)")
        }
    }
}

// MARK: - Errors

public enum StorageError: Error, CustomStringConvertible {
    case sessionNotFound(UUID)
    case runNotFound(UUID)
    case cannotWriteSession(UUID, String)
    case cannotReadSession(UUID, String)

    public var description: String {
        switch self {
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .runNotFound(let id):
            return "Run not found: \(id)"
        case .cannotWriteSession(let id, let reason):
            return "Cannot write session \(id): \(reason)"
        case .cannotReadSession(let id, let reason):
            return "Cannot read session \(id): \(reason)"
        }
    }
}
