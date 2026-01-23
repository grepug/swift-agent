import AnyLanguageModel
import Foundation
import SwiftAgentCore

@main
struct ExampleRunner {
    static func main() async throws {
        print("🤖 Swift Agent - Powered by AnyLanguageModel\n")

        // Check for API key
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            print("⚠️  Set OPENAI_API_KEY environment variable to run this example")
            print("Example: export OPENAI_API_KEY='your-key-here'\n")
            return
        }

        // Create OpenAI model
        let model = OpenAILanguageModel(
            apiKey: apiKey,
            model: "gpt-4o-mini"
        )

        // Create calculator tool
        let calculator = CalculatorTool()

        // Create an agent
        let agent = Agent(
            name: "AI Assistant",
            description: "A helpful AI assistant with calculator",
            model: model,
            instructions: "You are a helpful AI assistant. When asked to do calculations, use the calculator tool.",
            tools: [calculator]
        )

        print("Agent created: \(agent.name)")
        print("Session ID: \(agent.sessionId)")
        print("Model: OpenAI GPT-4o Mini\n")

        // Run the agent with a message
        let message = "What is 123 multiplied by 456?"
        print("User: \(message)\n")

        let run = try await agent.run(message: message)

        // Display results
        print("✅ Assistant: \(run.content ?? "No response")")
        print("\nRun ID: \(run.id)")
        print("Messages exchanged: \(run.messages.count)")
    }
}

// MARK: - Calculator Tool

struct CalculatorTool: Tool {
    var name: String { "calculator" }
    var description: String { "Performs basic arithmetic: add, subtract, multiply, divide" }

    @Generable
    struct Arguments: Codable {
        var operation: String
        var a: Double
        var b: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let result: Double
        switch arguments.operation.lowercased() {
        case "add":
            result = arguments.a + arguments.b
        case "subtract":
            result = arguments.a - arguments.b
        case "multiply":
            result = arguments.a * arguments.b
        case "divide":
            guard arguments.b != 0 else {
                throw ToolError.invalidArguments("Cannot divide by zero")
            }
            result = arguments.a / arguments.b
        default:
            throw ToolError.invalidArguments("Invalid operation: \(arguments.operation)")
        }
        return "\(result)"
    }
}

enum ToolError: Error {
    case invalidArguments(String)
}
