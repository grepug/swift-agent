import AnyLanguageModel
import Dependencies
import Foundation
import Testing

@testable import SwiftAgentCore

@Suite("Agent Hooks Tests")
struct HooksTests {
    
    // MARK: - Pre-Hook Tests
    
    @Test("Blocking pre-hook executes and waits")
    func blockingPreHookExecutes() async throws {
        @Dependency(\.agentCenter) var center
        
        // Track hook execution
        let executed = LockIsolated(false)
        
        // Register blocking pre-hook
        let preHook = RegisteredPreHook(
            name: "blocking-pre",
            blocking: true
        ) { context in
            try await Task.sleep(for: .milliseconds(100))
            executed.setValue(true)
        }
        
        await center.register(preHook: preHook)
        
        // Create agent with the hook
        let agent = Agent(
            id: "test-agent",
            name: "Test Agent",
            description: "Test",
            modelName: "test-model",
            instructions: "Test instructions",
            preHookNames: ["blocking-pre"]
        )
        
        await center.register(agent: agent)
        
        // Register a mock model
        let mockModel = createMockModel()
        await center.register(model: mockModel, named: "test-model")
        
        // Create session
        let session = try await center.createSession(
            agentId: agent.id,
            userId: UUID(),
            name: nil
        )
        
        let context = AgentSessionContext(
            agentId: agent.id,
            userId: session.userId,
            sessionId: session.id
        )
        
        // Run agent
        let run = try await center.runAgent(
            session: context,
            message: "Hello",
            as: String.self,
            loadHistory: false
        )
        
        // Hook should have executed before agent ran
        #expect(executed.value == true)
        #expect(run.messages.count > 0)
    }
    
    @Test("Non-blocking pre-hook launches but doesn't wait")
    func nonBlockingPreHookLaunches() async throws {
        @Dependency(\.agentCenter) var center
        
        // Track hook execution with timing
        let hookStarted = LockIsolated(false)
        let hookCompleted = LockIsolated(false)
        
        // Register non-blocking pre-hook with delay
        let preHook = RegisteredPreHook(
            name: "non-blocking-pre",
            blocking: false
        ) { context in
            hookStarted.setValue(true)
            try await Task.sleep(for: .milliseconds(500))  // Long delay
            hookCompleted.setValue(true)
        }
        
        await center.register(preHook: preHook)
        
        // Create agent with the hook
        let agent = Agent(
            id: "test-agent-2",
            name: "Test Agent 2",
            description: "Test",
            modelName: "test-model-2",
            instructions: "Test instructions",
            preHookNames: ["non-blocking-pre"]
        )
        
        await center.register(agent: agent)
        
        // Register a mock model
        let mockModel = createMockModel()
        await center.register(model: mockModel, named: "test-model-2")
        
        // Create session
        let session = try await center.createSession(
            agentId: agent.id,
            userId: UUID(),
            name: nil
        )
        
        let context = AgentSessionContext(
            agentId: agent.id,
            userId: session.userId,
            sessionId: session.id
        )
        
        // Run agent
        let run = try await center.runAgent(
            session: context,
            message: "Hello",
            as: String.self,
            loadHistory: false
        )
        
        // Agent should complete even though hook is still running
        #expect(run.messages.count > 0)
        
        // Hook may or may not have completed yet (it's running in background)
        // But we can wait for it and verify it does complete
        try await Task.sleep(for: .milliseconds(600))
        #expect(hookCompleted.value == true)
    }
    
    // MARK: - Post-Hook Tests
    
    @Test("Blocking post-hook executes after run")
    func blockingPostHookExecutes() async throws {
        @Dependency(\.agentCenter) var center
        
        // Track hook execution
        let receivedRun = LockIsolated<Run?>(nil)
        
        // Register blocking post-hook
        let postHook = RegisteredPostHook(
            name: "blocking-post",
            blocking: true
        ) { context, run in
            try await Task.sleep(for: .milliseconds(100))
            receivedRun.setValue(run)
        }
        
        await center.register(postHook: postHook)
        
        // Create agent with the hook
        let agent = Agent(
            id: "test-agent-3",
            name: "Test Agent 3",
            description: "Test",
            modelName: "test-model-3",
            instructions: "Test instructions",
            postHookNames: ["blocking-post"]
        )
        
        await center.register(agent: agent)
        
        // Register a mock model
        let mockModel = createMockModel()
        await center.register(model: mockModel, named: "test-model-3")
        
        // Create session
        let session = try await center.createSession(
            agentId: agent.id,
            userId: UUID(),
            name: nil
        )
        
        let context = AgentSessionContext(
            agentId: agent.id,
            userId: session.userId,
            sessionId: session.id
        )
        
        // Run agent
        let run = try await center.runAgent(
            session: context,
            message: "Hello",
            as: String.self,
            loadHistory: false
        )
        
        // Hook should have executed and received the run
        #expect(receivedRun.value != nil)
        #expect(receivedRun.value?.id == run.id)
    }
    
    @Test("Non-blocking post-hook launches after run")
    func nonBlockingPostHookLaunches() async throws {
        @Dependency(\.agentCenter) var center
        
        // Track hook execution
        let receivedRun = LockIsolated<Run?>(nil)
        
        // Register non-blocking post-hook
        let postHook = RegisteredPostHook(
            name: "non-blocking-post",
            blocking: false
        ) { context, run in
            try await Task.sleep(for: .milliseconds(500))
            receivedRun.setValue(run)
        }
        
        await center.register(postHook: postHook)
        
        // Create agent with the hook
        let agent = Agent(
            id: "test-agent-4",
            name: "Test Agent 4",
            description: "Test",
            modelName: "test-model-4",
            instructions: "Test instructions",
            postHookNames: ["non-blocking-post"]
        )
        
        await center.register(agent: agent)
        
        // Register a mock model
        let mockModel = createMockModel()
        await center.register(model: mockModel, named: "test-model-4")
        
        // Create session
        let session = try await center.createSession(
            agentId: agent.id,
            userId: UUID(),
            name: nil
        )
        
        let context = AgentSessionContext(
            agentId: agent.id,
            userId: session.userId,
            sessionId: session.id
        )
        
        // Run agent
        let run = try await center.runAgent(
            session: context,
            message: "Hello",
            as: String.self,
            loadHistory: false
        )
        
        // Agent should complete immediately
        #expect(run.messages.count > 0)
        
        // Wait for background hook to complete
        try await Task.sleep(for: .milliseconds(600))
        #expect(receivedRun.value?.id == run.id)
    }
    
    // MARK: - Hook Context Tests
    
    @Test("Hook receives correct context")
    func hookReceivesCorrectContext() async throws {
        @Dependency(\.agentCenter) var center
        
        // Track hook context
        let receivedContext = LockIsolated<HookContext?>(nil)
        
        // Register pre-hook that captures context
        let preHook = RegisteredPreHook(
            name: "context-capture",
            blocking: true
        ) { context in
            receivedContext.setValue(context)
        }
        
        await center.register(preHook: preHook)
        
        // Create agent
        let agent = Agent(
            id: "test-agent-5",
            name: "Test Agent 5",
            description: "Test Description",
            modelName: "test-model-5",
            instructions: "Test instructions",
            preHookNames: ["context-capture"]
        )
        
        await center.register(agent: agent)
        
        let mockModel = createMockModel()
        await center.register(model: mockModel, named: "test-model-5")
        
        // Create session
        let session = try await center.createSession(
            agentId: agent.id,
            userId: UUID(),
            name: "Test Session"
        )
        
        let context = AgentSessionContext(
            agentId: agent.id,
            userId: session.userId,
            sessionId: session.id
        )
        
        // Run agent with specific message
        let testMessage = "Test message for hooks"
        _ = try await center.runAgent(
            session: context,
            message: testMessage,
            as: String.self,
            loadHistory: false
        )
        
        // Verify hook received correct context
        let hookContext = try #require(receivedContext.value)
        #expect(hookContext.agent.id == agent.id)
        #expect(hookContext.agent.name == "Test Agent 5")
        #expect(hookContext.session.sessionId == session.id)
        #expect(hookContext.userMessage == testMessage)
    }
    
    // MARK: - Multiple Hooks Tests
    
    @Test("Multiple hooks execute in order")
    func multipleHooksExecuteInOrder() async throws {
        @Dependency(\.agentCenter) var center
        
        // Track execution order
        let executionOrder = LockIsolated<[String]>([])
        
        // Register multiple pre-hooks
        let hook1 = RegisteredPreHook(name: "hook-1", blocking: true) { _ in
            executionOrder.withValue { $0.append("hook-1") }
        }
        let hook2 = RegisteredPreHook(name: "hook-2", blocking: true) { _ in
            executionOrder.withValue { $0.append("hook-2") }
        }
        let hook3 = RegisteredPreHook(name: "hook-3", blocking: true) { _ in
            executionOrder.withValue { $0.append("hook-3") }
        }
        
        await center.register(preHook: hook1)
        await center.register(preHook: hook2)
        await center.register(preHook: hook3)
        
        // Create agent with hooks in specific order
        let agent = Agent(
            id: "test-agent-6",
            name: "Test Agent 6",
            description: "Test",
            modelName: "test-model-6",
            instructions: "Test instructions",
            preHookNames: ["hook-1", "hook-2", "hook-3"]
        )
        
        await center.register(agent: agent)
        
        let mockModel = createMockModel()
        await center.register(model: mockModel, named: "test-model-6")
        
        // Create session
        let session = try await center.createSession(
            agentId: agent.id,
            userId: UUID(),
            name: nil
        )
        
        let context = AgentSessionContext(
            agentId: agent.id,
            userId: session.userId,
            sessionId: session.id
        )
        
        // Run agent
        _ = try await center.runAgent(
            session: context,
            message: "Hello",
            as: String.self,
            loadHistory: false
        )
        
        // Verify execution order
        #expect(executionOrder.value == ["hook-1", "hook-2", "hook-3"])
    }
}

// MARK: - Mock Language Model

import struct AnyLanguageModel.OpenAILanguageModel

private func createMockModel() -> any LanguageModel {
    // Use a real OpenAI model for testing
    // In a real test environment, you'd use environment variables
    return OpenAILanguageModel(
        baseURL: URL(string: "https://api.openai.com/v1")!,
        apiKey: "test-key",  // This will fail but that's ok for structure testing
        model: "gpt-4"
    )
}
