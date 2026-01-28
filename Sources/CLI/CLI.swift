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

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context-agents",
        abstract: "A command-line tool for context-aware agents.",
        subcommands: [Session.self]
    )
}

struct Session: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage agent sessions",
        subcommands: [Create.self, List.self, Chat.self, Delete.self]
    )

    struct Create: MyParserableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new session"
        )

        @Option(name: .long, help: "Agent ID to use for this session")
        var agentId: String = "chat"

        @Option(name: .long, help: "User ID for this session")
        var userId: String?

        @Option(name: .long, help: "Optional friendly name for the session")
        var name: String?

        func runWithDependencies() async throws {
            @Dependency(\.agentCenter) var center
            @Dependency(\.storage) var storage
            @Dependency(\.userId) var defaultUserId

            let userId = userId.map { UUID(uuidString: $0)! } ?? defaultUserId

            let session = try await center.createSession(
                agentId: agentId,
                userId: userId,
                name: name
            )

            print("✅ Created session: \(session.id.uuidString)")
            print("   Agent ID: \(agentId)")
            print("   User ID: \(userId.uuidString)")
            print("   Message Count: \(session.messages.count)")
        }
    }

    struct List: MyParserableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all sessions"
        )

        @Option(name: .long, help: "Filter by agent ID")
        var agentId: String?

        @Option(name: .long, help: "Output format")
        var format: OutputFormat = .table

        enum OutputFormat: String, ExpressibleByArgument {
            case table, json, csv
        }

        func runWithDependencies() async throws {
            @Dependency(\.storage) var storage

            let sessions = try await storage.getSessions(
                agentId: agentId,
                userId: nil,
                limit: nil,
                offset: nil,
                sortBy: .updatedAtDesc
            )

            if sessions.isEmpty {
                print("No sessions found.")
                return
            }

            switch format {
            case .table:
                print("\nSessions (\(sessions.count) total):\n")

                // Print header
                let header =
                    "Session ID".padding(toLength: 36, withPad: " ", startingAt: 0) + " " + "Agent ID".padding(toLength: 15, withPad: " ", startingAt: 0) + " "
                    + "Name".padding(toLength: 20, withPad: " ", startingAt: 0) + " " + "Updated"
                print(header)
                print(String(repeating: "-", count: 95))

                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                dateFormatter.timeStyle = .short

                for session in sessions {
                    let sessionId = String(session.id.uuidString.prefix(36)).padding(toLength: 36, withPad: " ", startingAt: 0)
                    let agentId = String(session.agentId.prefix(15)).padding(toLength: 15, withPad: " ", startingAt: 0)
                    let name = String((session.name ?? "(unnamed)").prefix(20)).padding(toLength: 20, withPad: " ", startingAt: 0)
                    let updated = dateFormatter.string(from: session.updatedAt)
                    print("\(sessionId) \(agentId) \(name) \(updated)")
                }

            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(sessions)
                print(String(data: data, encoding: .utf8)!)

            case .csv:
                print("session_id,agent_id,user_id,name,created_at,updated_at")
                let dateFormatter = ISO8601DateFormatter()
                for session in sessions {
                    print(
                        "\(session.id.uuidString),\(session.agentId),\(session.userId.uuidString),\(session.name ?? ""),\(dateFormatter.string(from: session.createdAt)),\(dateFormatter.string(from: session.updatedAt))"
                    )
                }
            }
        }
    }

    struct Chat: MyParserableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Send a message to a session"
        )

        @Argument(help: "The message to send")
        var message: String

        @Option(
            name: .long, help: "Session ID to chat with",
            transform: {
                guard let uuid = UUID(uuidString: $0) else {
                    throw ValidationError("Invalid UUID format: \($0)")
                }
                return uuid
            })
        var sessionId: UUID

        @Option(name: .long, help: "Agent ID (creates temporary session if no session-id)")
        var agentId: String = "chat"

        func runWithDependencies() async throws {
            @Dependency(\.agentCenter) var center
            @Dependency(\.storage) var storage
            @Dependency(\.userId) var defaultUserId

            // Verify session exists
            guard
                let session = try await storage.getSession(
                    sessionId: sessionId,
                    agentId: agentId,
                    userId: defaultUserId
                )
            else {
                print("❌ Error: Session not found")
                return
            }

            print("💬 Chatting with session: \(sessionId.uuidString)")
            if let name = session.name {
                print("   Name: \(name)")
            }
            print("📤 Message: \(message)\n")

            // Create session context and run agent
            let context = AgentSessionContext(
                agentId: agentId,
                userId: defaultUserId,
                sessionId: sessionId
            )

            let run = try await center.runAgent(
                session: context,
                message: message,
                as: String.self,
                loadHistory: true
            )

            // Display response
            print("🤖 Agent response:")
            if let content = run.rawContent, let responseText = String(data: content, encoding: .utf8) {
                print(responseText)
            } else {
                print("(No content)")
            }

            print("\n✅ Run ID: \(run.id.uuidString)")
            print("   Session ID: \(sessionId.uuidString)")
        }
    }

    struct Delete: MyParserableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a session"
        )

        @Option(name: .long, help: "Session ID to delete")
        var sessionId: String

        func runWithDependencies() async throws {
            print("Deleted session: \(sessionId)")
        }
    }
}
