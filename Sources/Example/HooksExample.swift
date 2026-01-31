import AnyLanguageModel
import Configuration
import Dependencies
import Foundation
import SwiftAgentCore

/// Example demonstrating how to use agent hooks for logging and monitoring
@main
struct HooksExample {
    static func main() async throws {
        print("🎣 Agent Hooks Example\n")
        
        // Read configuration
        let reader = try EnvironmentReader()
        let apiKey = reader.string(forKey: "OPENAI_API_KEY")!
        
        @Dependency(\.agentCenter) var agentCenter
        
        // Create model
        let model = OpenAILanguageModel(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: apiKey,
            model: "gpt-4o-mini"
        )
        
        await agentCenter.register(model: model, named: "gpt-4o-mini")
        
        // MARK: - Define Hooks
        
        // 1. Logging Pre-Hook (non-blocking)
        let loggingPreHook = RegisteredPreHook(
            name: "request-logger",
            blocking: false
        ) { context in
            print("📝 [Pre-Hook] Agent: \(context.agent.name)")
            print("📝 [Pre-Hook] Message: \(context.userMessage)")
            print("📝 [Pre-Hook] Session: \(context.session.sessionId)")
            print()
        }
        
        // 2. Input Validation Pre-Hook (blocking)
        let validationPreHook = RegisteredPreHook(
            name: "input-validator",
            blocking: true
        ) { context in
            // Validate input isn't empty
            guard !context.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "ValidationError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Message cannot be empty"
                ])
            }
            
            // Validate message length
            guard context.userMessage.count <= 1000 else {
                throw NSError(domain: "ValidationError", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Message too long (max 1000 characters)"
                ])
            }
            
            print("✅ [Pre-Hook] Input validated")
        }
        
        // 3. Performance Monitoring Post-Hook (blocking)
        let performancePostHook = RegisteredPostHook(
            name: "performance-monitor",
            blocking: true
        ) { context, run in
            print("\n📊 [Post-Hook] Performance Metrics:")
            print("   - Messages: \(run.messages.count)")
            print("   - Duration: \(String(format: "%.2f", run.duration))s")
            print("   - Run ID: \(run.id)")
        }
        
        // 4. Analytics Post-Hook (non-blocking)
        let analyticsPostHook = RegisteredPostHook(
            name: "analytics",
            blocking: false
        ) { context, run in
            // Simulate sending analytics to external service
            try await Task.sleep(for: .seconds(1))
            print("\n📈 [Post-Hook] Analytics sent to external service")
            print("   - Agent: \(context.agent.name)")
            print("   - User: \(run.userId)")
            print("   - Timestamp: \(run.createdAt)")
        }
        
        // MARK: - Register Hooks
        
        await agentCenter.register(preHook: loggingPreHook)
        await agentCenter.register(preHook: validationPreHook)
        await agentCenter.register(postHook: performancePostHook)
        await agentCenter.register(postHook: analyticsPostHook)
        
        print("✅ Registered 4 hooks (2 pre-hooks, 2 post-hooks)\n")
        
        // MARK: - Create Agent with Hooks
        
        let assistant = Agent(
            id: "assistant",
            name: "AI Assistant",
            description: "A helpful assistant with hooks",
            modelName: "gpt-4o-mini",
            instructions: "You are a helpful AI assistant. Keep responses concise.",
            preHookNames: ["input-validator", "request-logger"],  // Blocking first, then non-blocking
            postHookNames: ["performance-monitor", "analytics"]   // Blocking first, then non-blocking
        )
        
        await agentCenter.register(agent: assistant)
        print("✅ Created agent with hooks\n")
        
        // MARK: - Run Agent
        
        let session = try await agentCenter.createSession(
            agentId: assistant.id,
            userId: UUID(),
            name: "Hooks Demo Session"
        )
        
        let context = AgentSessionContext(
            agentId: assistant.id,
            sessionId: session.id,
            userId: session.userId
        )
        
        print("🚀 Running agent with hooks...\n")
        print("=" + String(repeating: "=", count: 60))
        
        let run = try await agentCenter.runAgent(
            session: context,
            message: "What is Swift concurrency?",
            as: String.self,
            loadHistory: false
        )
        
        print("=" + String(repeating: "=", count: 60))
        
        // Extract response
        if let content = run.rawContent,
           let responseText = String(data: content, encoding: .utf8) {
            print("\n💬 Response: \(responseText)\n")
        }
        
        print("✅ Agent run completed")
        print("   Note: Analytics hook is still running in background\n")
        
        // Wait a bit for background hooks to complete
        print("⏳ Waiting for background hooks to complete...")
        try await Task.sleep(for: .seconds(2))
        
        print("\n✨ Example completed!")
    }
}
