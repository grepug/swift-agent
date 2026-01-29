import AnyLanguageModel
import ArgumentParser
import Configuration
import Dependencies
import Foundation
import SwiftAgentCore

protocol MyParserableCommand: AsyncParsableCommand {
    func runWithDependencies() async throws
}

extension MyParserableCommand {
    static func makeObservers() -> [any AgentCenterObserver] {
        // Check for debug directory from environment
        if let debugDir = ProcessInfo.processInfo.environment["SWIFT_AGENT_DEBUG_DIR"] {
            let url = URL(fileURLWithPath: debugDir)
            print("📊 Debug logging enabled to: \(debugDir)")
            return [
                // ConsoleObserver(verbose: false),
                FileDebugObserver(debugDir: url)
            ]
        }

        // Default: use .debug directory for debug traces
        let defaultDebugDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".debug")
        print("📊 Debug logging to: \(defaultDebugDir.path)")
        return [
            // ConsoleObserver(verbose: false),
            FileDebugObserver(debugDir: defaultDebugDir)
        ]
    }

    func run() async throws {
        // Configure observers FIRST, before any agent operations
        try await withDependencies {
            $0.agentObservers = Self.makeObservers()
        } operation: {
            @Dependency(\.agentCenter) var agentCenter

            let reader = ConfigReader(
                providers: [
                    try! await EnvironmentVariablesProvider(
                        environmentFilePath: ".env",
                        secretsSpecifier: .specific(["DOUBAO_API_KEY", "DOUBAO_API_URL", "DOUBAO_FLASH_MODEL_ID", "DOUBAO_1_6_ID"])
                    )
                ]
            )

            let apiKey = reader.string(forKey: "DOUBAO_API_KEY")!
            let baseURL = reader.string(forKey: "DOUBAO_API_URL")!
            let doubaoFlash = reader.string(forKey: "DOUBAO_FLASH_MODEL_ID")!
            // let doubao1_6Id = reader.string(forKey: "DOUBAO_1_6_ID")!

            // Create OpenAI model
            let doubaoModel = OpenAILanguageModel(
                baseURL: .init(string: baseURL)!,
                apiKey: apiKey,
                model: doubaoFlash,
            )

            let playwrightServer = MCPServerConfiguration(
                name: "PlaywrightMCP",
                transport: .stdio(
                    command: "npx",
                    arguments: ["@playwright/mcp@latest"]
                )
            )

            await agentCenter.register(tool: CommandTool())
            await agentCenter.register(agent: A.chatAgent)
            await agentCenter.register(agent: A.testAgent)
            await agentCenter.register(agent: A.practiceAgent)

            await agentCenter.register(
                model: doubaoModel,
                named: "doubao"
            )
            await agentCenter.register(
                mcpServerConfiguration: playwrightServer
            )

            try await runWithDependencies()
        }
    }
}
