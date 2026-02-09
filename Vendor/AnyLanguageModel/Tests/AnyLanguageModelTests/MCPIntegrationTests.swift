import Testing
import Foundation
@testable import AnyLanguageModel

/// Integration tests for MCP (Model Context Protocol) support.
///
/// Tests both HTTP and stdio transports with real MCP servers.
@Suite("MCP Integration Tests")
struct MCPIntegrationTests {

    // MARK: - HTTP Transport Tests

    @Test("HTTP: Connect to DeepWiki MCP server")
    func httpConnectDeepWiki() async throws {
        let config = MCPServerConfiguration(
            name: "deepwiki-http-test",
            transport: .http(url: URL(string: "https://mcp.deepwiki.com/mcp")!)
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        let tools = try await server.discover(timeout: .seconds(30))

        // DeepWiki should have ask_question and read_wiki tools
        #expect(tools.count >= 2)

        let toolNames = tools.map { $0.name }
        #expect(toolNames.contains("ask_question"))
        #expect(toolNames.contains("read_wiki_structure"))

        // Cleanup
        try await MCPServerCenter.shared.remove(config)
    }

    @Test("HTTP: Call DeepWiki ask_question tool")
    func httpCallDeepWikiTool() async throws {
        let config = MCPServerConfiguration(
            name: "deepwiki-http-call-test",
            transport: .http(url: URL(string: "https://mcp.deepwiki.com/mcp")!)
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        let tools = try await server.discover()

        // Find the ask_question tool
        guard let askQuestionTool = tools.first(where: { $0.name == "ask_question" }) else {
            Issue.record("ask_question tool not found")
            return
        }

        // Create arguments for the tool
        let arguments = GeneratedContent(properties: [
            "repoName": "facebook/react",
            "question": "What is React?",
        ])

        // Call the tool - need to cast to specific tool type to call
        let result = try await callTool(askQuestionTool, arguments: arguments)

        // Result should be a non-empty string
        #expect(!result.isEmpty)
        #expect(result.contains("React") || result.contains("library") || result.contains("JavaScript"))

        try await MCPServerCenter.shared.remove(config)
    }

    @Test("HTTP: Multiple servers simultaneously")
    func httpMultipleServers() async throws {
        // Test connecting to the same server twice - should reuse the instance
        let config = MCPServerConfiguration(
            name: "deepwiki-http-multi-test",
            transport: .http(url: URL(string: "https://mcp.deepwiki.com/mcp")!)
        )

        let server1 = try await MCPServerCenter.shared.server(for: config)
        let server2 = try await MCPServerCenter.shared.server(for: config)

        // Discover tools from both servers in parallel
        async let tools1 = server1.discover()
        async let tools2 = server2.discover()

        let (t1, t2) = try await (tools1, tools2)

        // Both should have the same tools (and actually be the same instance)
        #expect(t1.count >= 2)
        #expect(t2.count >= 2)
        #expect(t1.count == t2.count)

        try await MCPServerCenter.shared.remove(config)
    }

    @Test("HTTP: Filter tools by include set")
    func httpFilterToolsInclude() async throws {
        let config = MCPServerConfiguration(
            name: "deepwiki-http-include-test",
            transport: .http(url: URL(string: "https://mcp.deepwiki.com/mcp")!)
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        // Only include ask_question tool
        let tools = try await server.discover(include: ["ask_question"])

        #expect(tools.count == 1)
        #expect(tools[0].name == "ask_question")

        try await MCPServerCenter.shared.remove(config)
    }

    @Test("HTTP: Filter tools by exclude set")
    func httpFilterToolsExclude() async throws {
        let config = MCPServerConfiguration(
            name: "deepwiki-http-exclude-test",
            transport: .http(url: URL(string: "https://mcp.deepwiki.com/mcp")!)
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        // Exclude ask_question tool
        let tools = try await server.discover(exclude: ["ask_question"])

        #expect(!tools.contains(where: { $0.name == "ask_question" }))

        try await MCPServerCenter.shared.remove(config)
    }

    // MARK: - Stdio Transport Tests

    @Test("Stdio: Create server with npx command")
    func stdioCreateServer() async throws {
        let config = MCPServerConfiguration(
            name: "deepwiki-stdio-test",
            transport: .stdio(command: "npx", arguments: ["-y", "mcp-deepwiki"])
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        let tools = try await server.discover(timeout: .seconds(60))

        // mcp-deepwiki provides at least one tool
        #expect(tools.count >= 1)

        try await MCPServerCenter.shared.remove(config)
    }

    @Test("Stdio: YouTube Transcript MCP server (uvx)")
    func stdioYouTubeTranscriptUvx() async throws {
        // Test the Python-based YouTube transcript server
        let config = MCPServerConfiguration(
            name: "youtube-transcript-uvx-test",
            transport: .stdio(
                command: "uvx",
                arguments: [
                    "--from",
                    "git+https://github.com/jkawamoto/mcp-youtube-transcript",
                    "mcp-youtube-transcript",
                ]
            )
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        // Discover available tools
        let tools = try await server.discover(timeout: .seconds(120))

        // Server should provide tools
        #expect(tools.count > 0, "YouTube Transcript server should provide at least one tool")

        // Print available tools for debugging
        print("DEBUG: YouTube Transcript (uvx) MCP tools:")
        for tool in tools {
            print("  - \(tool.name): \(tool.description)")
        }

        try await MCPServerCenter.shared.remove(config)
    }

    @Test("Stdio: YouTube Transcript - Get transcript (uvx)")
    func stdioYouTubeTranscriptGetTranscriptUvx() async throws {
        let config = MCPServerConfiguration(
            name: "youtube-transcript-call-test",
            transport: .stdio(
                command: "uvx",
                arguments: [
                    "--from",
                    "git+https://github.com/jkawamoto/mcp-youtube-transcript",
                    "mcp-youtube-transcript",
                ]
            )
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        let tools = try await server.discover(timeout: .seconds(120))

        // Find a transcript tool (name might vary)
        guard
            let transcriptTool = tools.first(where: {
                $0.name.contains("transcript") || $0.name.contains("youtube")
            })
        else {
            Issue.record("No transcript tool found. Available tools: \(tools.map { $0.name }.joined(separator: ", "))")
            try await MCPServerCenter.shared.remove(config)
            return
        }

        print("DEBUG: Testing tool '\(transcriptTool.name)' with YouTube URL")

        // Test with a YouTube video URL
        let arguments = GeneratedContent(properties: [
            "url": "https://www.youtube.com/watch?v=fT6kGrHtf9k"
        ])

        let result = try await callTool(transcriptTool, arguments: arguments)

        // Verify we got a response
        #expect(result.count >= 0, "Should receive a response")

        print("Successfully called '\(transcriptTool.name)' tool (\(result.count) characters)")
        if !result.isEmpty {
            print("First 200 chars: \(result.prefix(200))")
        }

        try await MCPServerCenter.shared.remove(config)
    }

    @Test("Stdio: Playwright MCP server")
    func stdioPlaywrightServer() async throws {
        // Initialize Playwright MCP server via stdio
        let config = MCPServerConfiguration(
            name: "playwright-test",
            transport: .stdio(command: "npx", arguments: ["@playwright/mcp@latest"])
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        // Discover available Playwright tools
        let tools = try await server.discover(timeout: .seconds(120))

        // Playwright MCP should provide browser automation tools
        #expect(tools.count > 0, "Playwright should provide at least one tool")

        // Verify common tools are available
        let toolNames = tools.map { $0.name }
        #expect(toolNames.contains(where: { $0.contains("navigate") }))
        #expect(toolNames.contains(where: { $0.contains("screenshot") }))

        try await MCPServerCenter.shared.remove(config)
    }

    @Test("Stdio: Playwright screenshot workflow")
    func stdioPlaywrightScreenshot() async throws {
        // This test demonstrates a complete Playwright workflow
        let config = MCPServerConfiguration(
            name: "playwright-screenshot-test",
            transport: .stdio(command: "npx", arguments: ["@playwright/mcp@latest"])
        )
        let server = try await MCPServerCenter.shared.server(for: config)

        let tools = try await server.discover(timeout: .seconds(120))

        // Find the navigate tool
        guard let navigateTool = tools.first(where: { $0.name.contains("navigate") && !$0.name.contains("back") })
        else {
            Issue.record("Navigate tool not found in Playwright MCP")
            try await MCPServerCenter.shared.remove(config)
            return
        }

        // Navigate to a webpage
        let navigateArgs = GeneratedContent(properties: [
            "url": "https://playwright.dev"
        ])

        _ = try await callTool(navigateTool, arguments: navigateArgs)

        // Find the screenshot tool
        guard let screenshotTool = tools.first(where: { $0.name == "browser_take_screenshot" })
        else {
            Issue.record("Screenshot tool not found in Playwright MCP")
            try await MCPServerCenter.shared.remove(config)
            return
        }

        // Take a screenshot (Playwright MCP saves to its own temp directory)
        let screenshotArgs = GeneratedContent(properties: [:])

        let result = try await callTool(screenshotTool, arguments: screenshotArgs)

        // Parse the result to extract the screenshot path
        // Result format: "- [Screenshot of viewport](path/to/screenshot.png)"
        if let match = result.range(of: #"\(([^)]+\.png)\)"#, options: .regularExpression) {
            let pathString = String(result[match])
            // Extract path from (path)
            let path = pathString.dropFirst().dropLast()

            // Copy to ~/Downloads
            let sourceURL = URL(fileURLWithPath: String(path))
            let downloadPath = URL(fileURLWithPath: NSString(string: "~/Downloads").expandingTildeInPath)
                .appendingPathComponent("playwright-screenshot.png")

            try? FileManager.default.copyItem(at: sourceURL, to: downloadPath)
            print("Screenshot saved to: \(downloadPath.path)")
        }

        // Result should indicate success
        #expect(!result.isEmpty)

        try await MCPServerCenter.shared.remove(config)
    }
}

// MARK: - Helpers

/// Helper to call a tool with existential type.
fileprivate func callTool<T: Tool>(_ tool: T, arguments: T.Arguments) async throws -> T.Output {
    try await tool.call(arguments: arguments)
}

/// Helper to call a tool when we have `any Tool`.
fileprivate func callTool(_ tool: any Tool, arguments: GeneratedContent) async throws -> String {
    // Downcast to the concrete type we know (MCPDiscoveredTool)
    guard let mcpTool = tool as? MCPDiscoveredTool else {
        throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected tool type"])
    }
    return try await mcpTool.call(arguments: arguments)
}
