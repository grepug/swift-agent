import Foundation
import SwiftAgentCore

@main
struct ExampleRunner {
    static func main() async throws {
        print("🤖 Swift Agent - Minimal Implementation Demo\n")

        // Create a mock model
        let model = MockModel(responses: ["Hello! I can help you with calculations and questions."])

        // Create an agent
        let agent = Agent(
            name: "Demo Agent",
            description: "A simple agent for demonstration",
            model: model,
            instructions: [
                "You are a helpful assistant.",
                "You can perform calculations using the calculator tool.",
            ],
            tools: [CalculatorTool()]
        )

        print("Agent created: \(agent.name)")
        print("Session ID: \(agent.sessionId)")
        print("Instructions: \(agent.instructions.joined(separator: " "))\n")

        // Run the agent with a message
        print("Running agent with message: 'Hello!'\n")
        let run = try await agent.run(message: "Hello!")

        // Display results
        print("Run ID: \(run.id)")
        print("Messages exchanged: \(run.messages.count)")
        print("\nConversation:")
        for (index, message) in run.messages.enumerated() {
            let content = message.content ?? "(tool call)"
            print("\(index + 1). [\(message.role.rawValue)] \(content)")
        }

        print("\n✅ Final response: \(run.content ?? "No response")")
    }
}
