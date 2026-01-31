import Dependencies
import Foundation
import Testing

@testable import SwiftAgentCore

/// Integration tests focused on verifying the refactored Storage protocol
/// Tests the Session -> Runs -> Messages data model without requiring a real LLM
@Suite("Storage Integration Tests")
struct StorageIntegrationTests {
    
    // MARK: - Test 1: Basic Run Storage and Retrieval
    
    @Test("Store run and verify messages are accessible through session")
    func testBasicRunStorage() async throws {
        // Given: A storage and a session
        let storage = InMemoryAgentStorage()
        let userId = UUID()
        let agentId = "test-agent"
        
        let session = AgentSession(
            agentId: agentId,
            userId: userId,
            name: "Test Session",
            runs: []
        )
        let savedSession = try await storage.upsertSession(session)
        
        // When: We create and save a run with messages
        let userMessage = Message.user("Hello, agent!")
        let assistantMessage = Message.assistant("Hello, user!")
        
        let run = Run(
            agentId: agentId,
            sessionId: savedSession.id,
            userId: userId,
            messages: [userMessage, assistantMessage]
        )
        
        try await storage.appendRun(run, sessionId: savedSession.id)
        
        // Then: The session should contain the run
        let updatedSession = try await storage.getSession(
            sessionId: savedSession.id,
            agentId: agentId,
            userId: userId
        )
        
        #expect(updatedSession != nil)
        #expect(updatedSession!.runs.count == 1)
        #expect(updatedSession!.runs.first?.id == run.id)
        
        // And: Messages should be accessible through the run
        let savedRun = updatedSession!.runs.first!
        #expect(savedRun.messages.count == 2)
        #expect(savedRun.messages[0].content == "Hello, agent!")
        #expect(savedRun.messages[1].content == "Hello, user!")
        
        // And: Messages should also be accessible through allMessages computed property
        #expect(updatedSession!.allMessages.count == 2)
        #expect(updatedSession!.allMessages[0].content == "Hello, agent!")
        #expect(updatedSession!.allMessages[1].content == "Hello, user!")
    }
    
    // MARK: - Test 2: Multiple Runs in Single Session
    
    @Test("Store multiple runs and verify message ordering")
    func testMultipleRunsInSession() async throws {
        // Given: A storage and a session
        let storage = InMemoryAgentStorage()
        let userId = UUID()
        let agentId = "test-agent"
        
        let session = AgentSession(
            agentId: agentId,
            userId: userId,
            name: "Test Session",
            runs: []
        )
        let savedSession = try await storage.upsertSession(session)
        
        // When: We create multiple runs
        let run1 = Run(
            agentId: agentId,
            sessionId: savedSession.id,
            userId: userId,
            messages: [
                Message.user("First question"),
                Message.assistant("First answer")
            ]
        )
        
        try await storage.appendRun(run1, sessionId: savedSession.id)
        
        // Small delay to ensure different timestamps
        try await Task.sleep(for: .milliseconds(10))
        
        let run2 = Run(
            agentId: agentId,
            sessionId: savedSession.id,
            userId: userId,
            messages: [
                Message.user("Second question"),
                Message.assistant("Second answer")
            ]
        )
        
        try await storage.appendRun(run2, sessionId: savedSession.id)
        
        // Then: Session should contain both runs in correct order
        let updatedSession = try await storage.getSession(
            sessionId: savedSession.id,
            agentId: agentId,
            userId: userId
        )
        
        #expect(updatedSession != nil)
        #expect(updatedSession!.runs.count == 2)
        #expect(updatedSession!.runs[0].id == run1.id)
        #expect(updatedSession!.runs[1].id == run2.id)
        
        // And: allMessages should contain all messages in order
        #expect(updatedSession!.allMessages.count == 4)
        #expect(updatedSession!.allMessages[0].content == "First question")
        #expect(updatedSession!.allMessages[1].content == "First answer")
        #expect(updatedSession!.allMessages[2].content == "Second question")
        #expect(updatedSession!.allMessages[3].content == "Second answer")
    }
    
    // MARK: - Test 3: Session Isolation
    
    @Test("Multiple sessions maintain message isolation")
    func testSessionIsolation() async throws {
        // Given: A storage with two different sessions
        let storage = InMemoryAgentStorage()
        let userId = UUID()
        let agentId = "test-agent"
        
        let session1 = AgentSession(
            agentId: agentId,
            userId: userId,
            name: "Session 1",
            runs: []
        )
        let savedSession1 = try await storage.upsertSession(session1)
        
        let session2 = AgentSession(
            agentId: agentId,
            userId: userId,
            name: "Session 2",
            runs: []
        )
        let savedSession2 = try await storage.upsertSession(session2)
        
        // When: We save runs to different sessions
        let run1 = Run(
            agentId: agentId,
            sessionId: savedSession1.id,
            userId: userId,
            messages: [Message.user("Session 1 message")]
        )
        
        let run2 = Run(
            agentId: agentId,
            sessionId: savedSession2.id,
            userId: userId,
            messages: [Message.user("Session 2 message")]
        )
        
        try await storage.appendRun(run1, sessionId: savedSession1.id)
        try await storage.appendRun(run2, sessionId: savedSession2.id)
        
        // Then: Each session should only contain its own messages
        let updatedSession1 = try await storage.getSession(
            sessionId: savedSession1.id,
            agentId: agentId,
            userId: userId
        )
        
        let updatedSession2 = try await storage.getSession(
            sessionId: savedSession2.id,
            agentId: agentId,
            userId: userId
        )
        
        #expect(updatedSession1 != nil)
        #expect(updatedSession1!.runs.count == 1)
        #expect(updatedSession1!.allMessages.count == 1)
        #expect(updatedSession1!.allMessages[0].content == "Session 1 message")
        
        #expect(updatedSession2 != nil)
        #expect(updatedSession2!.runs.count == 1)
        #expect(updatedSession2!.allMessages.count == 1)
        #expect(updatedSession2!.allMessages[0].content == "Session 2 message")
    }
    
    // MARK: - Test 4: File Storage Persistence
    
    @Test("FileAgentStorage persists sessions and runs across instances")
    func testFileStoragePersistence() async throws {
        // Given: A temporary directory and file storage
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let userId = UUID()
        let agentId = "test-agent"
        
        // When: We create a session and run with first storage instance
        do {
            let storage1 = FileAgentStorage(rootPath: tempDir.path())
            
            let session = AgentSession(
                agentId: agentId,
                userId: userId,
                name: "Persistent Session",
                runs: []
            )
            let savedSession = try await storage1.upsertSession(session)
            
            let run = Run(
                agentId: agentId,
                sessionId: savedSession.id,
                userId: userId,
                messages: [
                    Message.user("Persistent message"),
                    Message.assistant("Persistent response")
                ]
            )
            
            try await storage1.appendRun(run, sessionId: savedSession.id)
        }
        
        // Then: A new storage instance should load the persisted data
        do {
            let storage2 = FileAgentStorage(rootPath: tempDir.path())
            
            let sessions = try await storage2.getSessions(
                agentId: agentId,
                userId: userId,
                limit: nil,
                offset: nil,
                sortBy: nil
            )
            
            #expect(sessions.count == 1)
            
            let loadedSession = sessions[0]
            #expect(loadedSession.runs.count == 1)
            #expect(loadedSession.allMessages.count == 2)
            #expect(loadedSession.allMessages[0].content == "Persistent message")
            #expect(loadedSession.allMessages[1].content == "Persistent response")
        }
    }
    
    // MARK: - Test 5: Empty Session Handling
    
    @Test("New session has empty runs and messages")
    func testEmptySessionHandling() async throws {
        // Given: A new session
        let storage = InMemoryAgentStorage()
        let userId = UUID()
        let agentId = "test-agent"
        
        // When: We create a session without any runs
        let session = AgentSession(
            agentId: agentId,
            userId: userId,
            name: "Empty Session",
            runs: []
        )
        let savedSession = try await storage.upsertSession(session)
        
        // Then: The session should have empty runs and messages
        #expect(session.runs.isEmpty)
        #expect(session.allMessages.isEmpty)
        
        // And: Retrieving it should maintain that state
        let retrievedSession = try await storage.getSession(
            sessionId: savedSession.id,
            agentId: agentId,
            userId: userId
        )
        
        #expect(retrievedSession != nil)
        #expect(retrievedSession!.runs.isEmpty)
        #expect(retrievedSession!.allMessages.isEmpty)
    }
    
    // MARK: - Test 6: Message Ordering in Runs
    
    @Test("Messages within a run maintain insertion order")
    func testMessageOrderingWithinRun() async throws {
        // Given: A storage and session
        let storage = InMemoryAgentStorage()
        let userId = UUID()
        let agentId = "test-agent"
        
        let session = AgentSession(
            agentId: agentId,
            userId: userId,
            name: "Ordering Test",
            runs: []
        )
        let savedSession = try await storage.upsertSession(session)
        
        // When: We create a run with multiple messages in specific order
        let messages = [
            Message.system("You are a helpful assistant"),
            Message.user("Hello"),
            Message.assistant("Hi there!"),
            Message.user("How are you?"),
            Message.assistant("I'm doing well, thank you!")
        ]
        
        let run = Run(
            agentId: agentId,
            sessionId: savedSession.id,
            userId: userId,
            messages: messages
        )
        
        try await storage.appendRun(run, sessionId: savedSession.id)
        
        // Then: Messages should be retrieved in exact same order
        let updatedSession = try await storage.getSession(
            sessionId: savedSession.id,
            agentId: agentId,
            userId: userId
        )
        
        #expect(updatedSession != nil)
        let retrievedMessages = updatedSession!.allMessages
        
        #expect(retrievedMessages.count == 5)
        #expect(retrievedMessages[0].role == MessageRole.system)
        #expect(retrievedMessages[0].content == "You are a helpful assistant")
        #expect(retrievedMessages[1].role == MessageRole.user)
        #expect(retrievedMessages[1].content == "Hello")
        #expect(retrievedMessages[2].role == MessageRole.assistant)
        #expect(retrievedMessages[2].content == "Hi there!")
        #expect(retrievedMessages[3].role == MessageRole.user)
        #expect(retrievedMessages[3].content == "How are you?")
        #expect(retrievedMessages[4].role == MessageRole.assistant)
        #expect(retrievedMessages[4].content == "I'm doing well, thank you!")
    }
    
    // MARK: - Test 7: Stats Calculation
    
    @Test("Storage stats correctly count runs instead of messages")
    func testStorageStatsCalculation() async throws {
        // Given: A storage with multiple sessions and runs
        let storage = InMemoryAgentStorage()
        let userId = UUID()
        let agentId = "test-agent"
        
        // Create first session with 2 runs
        let session1 = AgentSession(
            agentId: agentId,
            userId: userId,
            name: "Stats Session 1",
            runs: []
        )
        let savedSession1 = try await storage.upsertSession(session1)
        
        try await storage.appendRun(Run(
            agentId: agentId,
            sessionId: savedSession1.id,
            userId: userId,
            messages: [Message.user("Q1"), Message.assistant("A1")]
        ), sessionId: savedSession1.id)
        
        try await storage.appendRun(Run(
            agentId: agentId,
            sessionId: savedSession1.id,
            userId: userId,
            messages: [Message.user("Q2"), Message.assistant("A2")]
        ), sessionId: savedSession1.id)
        
        // Create second session with 1 run
        let session2 = AgentSession(
            agentId: agentId,
            userId: userId,
            name: "Stats Session 2",
            runs: []
        )
        let savedSession2 = try await storage.upsertSession(session2)
        
        try await storage.appendRun(Run(
            agentId: agentId,
            sessionId: savedSession2.id,
            userId: userId,
            messages: [Message.user("Q3"), Message.assistant("A3")]
        ), sessionId: savedSession2.id)
        
        // When: We get storage stats
        let stats = try await storage.getStats()
        
        // Then: Stats should reflect correct run counts
        #expect(stats.totalSessions == 2)
        #expect(stats.totalRuns == 3)
        #expect(stats.totalMessages == 6) // 2+2+2 messages across all runs
    }
}
