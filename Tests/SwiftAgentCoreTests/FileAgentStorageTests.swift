import Foundation
import Testing

@testable import SwiftAgentCore

@Test func testFileAgentStorageWithSortableNames() async throws {
    // Create temporary directory for this test
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-storage-\(UUID().uuidString)")

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    let storage = FileAgentStorage(rootPath: tempDir.path)

    // Create a session
    let userId = UUID()
    let session1 = AgentSession(
        id: UUID(),
        agentId: "test-agent",
        userId: userId,
        name: "First Session",
        messages: [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!"),
        ]
    )

    _ = try await storage.upsertSession(session1)

    // Wait a bit and create another session to ensure different timestamps
    try await Task.sleep(for: .seconds(1))

    let session2 = AgentSession(
        id: UUID(),
        agentId: "test-agent",
        userId: userId,
        name: "Second Session"
    )

    _ = try await storage.upsertSession(session2)

    // Retrieve sessions
    let sessions = try await storage.getSessions(agentId: "test-agent", userId: nil)
    #expect(sessions.count == 2)

    // Check that directories have sortable names
    let agentDir =
        tempDir
        .appendingPathComponent("agents/test-agent/sessions")

    let sessionDirs = try FileManager.default.contentsOfDirectory(
        at: agentDir,
        includingPropertiesForKeys: nil
    ).filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    print("📁 Session directories (sorted by name):")
    for dir in sessionDirs {
        print("  - \(dir.lastPathComponent)")
        let sessionFile = dir.appendingPathComponent("session.json")
        if let data = try? Data(contentsOf: sessionFile),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = json["name"] as? String
        {
            print("    Session name: \(name)")
        }
    }

    // Verify directories are named with timestamps (yyyyMMddHHmmss-xxxxxx)
    for dir in sessionDirs {
        let name = dir.lastPathComponent
        #expect(name.count == 21)  // 14 (timestamp) + 1 (dash) + 6 (uuid prefix)
        #expect(name.contains("-"))

        let parts = name.split(separator: "-")
        #expect(parts.count == 2)
        #expect(parts[0].count == 14)  // Timestamp
        #expect(parts[1].count == 6)  // UUID prefix
    }

    // Test appending a run
    let run = Run(
        agentId: "test-agent",
        sessionId: session1.id,
        userId: userId,
        messages: [],
        status: .completed,
        modelName: "test-model",
        metrics: RunMetrics(inputTokens: 100, outputTokens: 50, totalTokens: 150)
    )

    try await storage.appendRun(run, sessionId: session1.id)

    // Retrieve and verify
    let updatedSession = try await storage.getSession(sessionId: session1.id)
    #expect(updatedSession?.runs.count == 1)
    #expect(updatedSession?.runs.first?.metrics?.totalTokens == 150)

    // Test stats
    let stats = try await storage.getStats()
    #expect(stats.totalSessions == 2)
    #expect(stats.totalRuns == 1)
    #expect(stats.totalMessages == 2)
}

@Test func testFileAgentStorageSessionOperations() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-storage-\(UUID().uuidString)")

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    let storage = FileAgentStorage(rootPath: tempDir.path)

    let userId = UUID()
    let sessionId = UUID()

    // Create session
    let session = AgentSession(
        id: sessionId,
        agentId: "my-agent",
        userId: userId,
        sessionData: ["key1": AnyCodable("\"value1\"")]  // Store as JSON string
    )

    _ = try await storage.upsertSession(session)

    // Update session data (merge)
    try await storage.updateSessionData(
        ["key2": AnyCodable("\"value2\"")],  // Store as JSON string
        sessionId: sessionId,
        merge: true
    )

    let data = try await storage.getSessionData(sessionId: sessionId)
    #expect(try data?["key1"]?.decode(as: String.self) == "value1")
    #expect(try data?["key2"]?.decode(as: String.self) == "value2")

    // Update session data (replace)
    try await storage.updateSessionData(
        ["key3": AnyCodable("\"value3\"")],  // Store as JSON string
        sessionId: sessionId,
        merge: false
    )

    let newData = try await storage.getSessionData(sessionId: sessionId)
    #expect(newData?["key1"] == nil)
    #expect(try newData?["key3"]?.decode(as: String.self) == "value3")

    // Rename session
    _ = try await storage.renameSession(sessionId: sessionId, name: "Updated Name")
    let renamed = try await storage.getSession(sessionId: sessionId)
    #expect(renamed?.name == "Updated Name")

    // Delete session
    let deleted = try await storage.deleteSession(sessionId: sessionId)
    #expect(deleted == true)

    let retrieved = try await storage.getSession(sessionId: sessionId)
    #expect(retrieved == nil)
}
