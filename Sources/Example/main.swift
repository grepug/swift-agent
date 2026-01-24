import AnyLanguageModel
import Configuration
import Foundation
import SwiftAgentCore

@main
struct ExampleRunner {
    static func main() async throws {
        let config = ConfigReader(
            providers: [
                try! await EnvironmentVariablesProvider(
                    environmentFilePath: ".env",
                    secretsSpecifier: .specific(["DOUBAO_API_KEY"])
                )
            ]
        )

        let apiKey = config.string(forKey: "DOUBAO_API_KEY")!
        let baseURL = config.string(forKey: "DOUBAO_API_URL")!
        let doubaoFlashModelId = config.string(forKey: "DOUBAO_FLASH_MODEL_ID")!
        let doubao1_6Id = config.string(forKey: "DOUBAO_1_6_ID")!

        // Create OpenAI model
        let doubaoModel = OpenAILanguageModel(
            baseURL: .init(string: baseURL)!,
            apiKey: apiKey,
            model: doubao1_6Id,
        )

        // Create calculator tool
        let calculator = CalculatorTool()

        // Create an agent
        let agent = Agent(
            name: "AI Assistant",
            description: "A helpful AI assistant with calculator",
            model: doubaoModel,
            instructions: """
                You are a helpful AI assistant. 
                When asked to do calculations, use the calculator tool.
                If not asked to do calculations, don't use tool.
                """,
            tools: [calculator]
        )

        print("Agent created: \(agent.name)")
        print("Session ID: \(agent.sessionId)")
        print("Model: \(doubaoFlashModelId)\n")

        // Example 1: Regular run with tool calling
        print("=== Example 1: Tool Calling ===")
        let message = "What are 123^123 and 123 + 123?"
        print("User: \(message)\n")

        let run = try await agent.run(message: message, as: String.self)
        print("✅ Assistant: \(try run.asString())")
        print("Run ID: \(run.id)")
        print("Messages: \(run.messages.count)\n")

        // Example 2: Structured output using schema injection
        print("\n=== Example 2: Structured Output ===")
        let moviePrompt = "Recommend 3 sci-fi movie about AI"
        print("User: \(moviePrompt)\n")

        let run2 = try await agent.run(
            message: moviePrompt,
            as: [MovieRecommendation].self,
            loadHistory: false,
        )

        let decoded = try run2.decoded(as: [MovieRecommendation].self)

        print("✅ Movie Recommendations:", decoded)
    }
}

// MARK: - Structured Output Types (for future use)

@Generable
struct MovieRecommendation: Codable {
    @Guide(description: "The movie title")
    var title: String

    @Guide(description: "The year it was released", .range(1900...2030))
    var year: Int

    @Guide(description: "Rating from 1-10", .range(1...10))
    var rating: Double

    @Guide(description: "Brief plot summary")
    var summary: String

    @Guide(description: "Name of the director")
    var director: String
}

// MARK: - Calculator Tool

struct CalculatorTool: Tool {
    var name: String {
        "calculator"
    }

    var description: String {
        "Performs basic arithmetic: add, subtract, multiply, divide, power"
    }

    @Generable
    struct Arguments: Codable {
        @Guide(description: "add, subtract, multiply, divide, power, if calculate ^, use power")
        var operation: String
        var a: Double
        var b: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let result: Double
        switch arguments.operation.lowercased() {
        case "add":
            result = arguments.a + arguments.b
            print("use add")
        case "subtract":
            result = arguments.a - arguments.b
        case "multiply":
            result = arguments.a * arguments.b
            print("use multiple")
        case "divide":
            guard arguments.b != 0 else {
                throw ToolError.invalidArguments("Cannot divide by zero")
            }
            result = arguments.a / arguments.b
        case "power":
            result = pow(arguments.a, arguments.b)
            print("use power")
        default:
            throw ToolError.invalidArguments("Invalid operation: \(arguments.operation)")
        }
        return "\(result)"
    }
}

enum ToolError: Error {
    case invalidArguments(String)
}
