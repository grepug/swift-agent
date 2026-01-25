import AnyLanguageModel
import Configuration
import Foundation
import Logging
import SwiftAgentCore

@main
struct ExampleRunner {
    static func makeConfig() async -> ConfigReader {
        ConfigReader(
            providers: [
                try! await EnvironmentVariablesProvider(
                    environmentFilePath: ".env",
                    secretsSpecifier: .specific(["DOUBAO_API_KEY", "DOUBAO_API_URL", "DOUBAO_FLASH_MODEL_ID", "DOUBAO_1_6_ID"])
                )
            ]
        )
    }

    static func model(config: ConfigReader) -> OpenAILanguageModel {
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

        return doubaoModel
    }

    static func getAgent() async throws -> Agent {
        let context7Server = MCPServerConfiguration(
            name: "Context7",
            transport: .http(
                url: URL(string: "https://mcp.context7.com/mcp")!,
                headers: ["CONTEXT7_API_KEY": "ctx7sk-8ab14c08-6413-4e21-b9b8-3ac050362087"]
            )
        )

        let deepwikiServer = MCPServerConfiguration(
            name: "DeepWiki",
            transport: .http(
                url: URL(string: "https://mcp.deepwiki.com/mcp")!
            )
        )

        let playwrightServer = MCPServerConfiguration(
            name: "PlaywrightMCP",
            transport: .stdio(
                command: "npx",
                arguments: ["@playwright/mcp@latest"]
            )
        )

        let tavilyServer = MCPServerConfiguration(
            name: "Tavily",
            transport: .http(
                url: URL(string: "https://mcp.tavily.com/mcp")!,
                headers: ["Authorization": "Bearer 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"]
            )
        )

        let youtubeTranscriptServer = MCPServerConfiguration(
            name: "YouTubeTranscript",
            transport: .stdio(
                command: "uvx",
                arguments: [
                    "--from",
                    "git+https://github.com/jkawamoto/mcp-youtube-transcript",
                    "mcp-youtube-transcript",
                ]
            )
        )

        // Create calculator tool
        let calculator = CalculatorTool()
        let doubaoModel = await model(config: makeConfig())

        // Create an agent
        let agent = Agent(
            name: "AI Assistant",
            description: "A helpful AI assistant with calculator",
            model: doubaoModel,
            instructions: """
                You are a helpful AI assistant. 
                When asked to do calculations, use the calculator tool.
                If not asked to do calculations, don't use tool.
                If user asks for information about a gihub repository, use the MCP tools to fetch the information.
                If user asks for browsing the web, use the Playwright MCP tool to fetch the information.
                If user asks for general knowledge questions, use the Tavily MCP tool to fetch the information.
                If user asks for YouTube transcript, use the YouTube Transcript MCP tool to fetch the information.
                """,
            tools: [calculator],
            mcpServers: [
                context7Server,
                deepwikiServer,
                playwrightServer,
                tavilyServer,
                youtubeTranscriptServer,
            ],
        )

        let center = AgentCenter(agents: [agent])
        try await center.start()

        return try await center.useAgent(
            id: agent.id,
            sessionId: UUID(),
            userId: UUID()
        )
    }

    static func getAgent2() async throws -> Agent {
        let config = await makeConfig()
        let agent = Agent(
            id: UUID(),
            name: "xxxx",
            model: model(config: config),
            instructions: """

                """,
            tools: []
        )

        return agent
    }

    static func main() async throws {
        LoggingSystem.bootstrap(ModernOSLogHandler.init)

        let agent = try await getAgent()

        print("Agent created: \(agent.name)")
        print("Session ID: \(agent.sessionId)")

        // Example 1: Regular run with tool calling
        print("=== Example 1: Tool Calling ===")
        // let message = "What are 123^123 and 123 + 123?"
        let message = "summerize https://www.youtube.com/watch?v=fT6kGrHtf9k"
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

#if canImport(os)
    import Logging
    import os

    extension ExampleRunner {
        struct ModernOSLogHandler: LogHandler {
            public var logLevel: Logging.Logger.Level = .debug
            public var metadata: Logging.Logger.Metadata = [:]
            private let osLogger: os.Logger

            public init(label: String) {
                // Split label into subsystem and category
                let components = label.split(separator: ".", maxSplits: 2)
                let subsystem =
                    components.count > 1
                    ? components[0..<components.count - 1].joined(separator: ".")
                    : label
                let category = components.last.map(String.init) ?? "default"

                self.osLogger = os.Logger(subsystem: subsystem, category: category)
            }

            public func log(
                level: Logging.Logger.Level,
                message: Logging.Logger.Message,
                metadata: Logging.Logger.Metadata?,
                source: String,
                file: String,
                function: String,
                line: UInt
            ) {
                let mergedMetadata = self.metadata.merging(metadata ?? [:]) { $1 }

                // Use modern Logger API with privacy controls
                switch level {
                case .trace, .debug:
                    osLogger.debug("\(message.description, privacy: .public) \(formatMetadata(mergedMetadata), privacy: .public)")
                case .info:
                    osLogger.info("\(message.description, privacy: .public) \(formatMetadata(mergedMetadata), privacy: .public)")
                case .notice:
                    osLogger.notice("\(message.description, privacy: .public) \(formatMetadata(mergedMetadata), privacy: .public)")
                case .warning:
                    osLogger.warning("\(message.description, privacy: .public) \(formatMetadata(mergedMetadata), privacy: .public)")
                case .error:
                    osLogger.error("\(message.description, privacy: .public) \(formatMetadata(mergedMetadata), privacy: .public)")
                case .critical:
                    osLogger.critical("\(message.description, privacy: .public) \(formatMetadata(mergedMetadata), privacy: .public)")
                }
            }

            private func formatMetadata(_ metadata: Logging.Logger.Metadata) -> String {
                guard !metadata.isEmpty else { return "" }
                return metadata.map { "\($0)=\($1)" }.joined(separator: " ")
            }

            public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
                get { metadata[key] }
                set { metadata[key] = newValue }
            }
        }
    }

#endif
