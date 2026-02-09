import Foundation
import Logging

private let logger = Logger(label: "AnyLanguageModel.MCPTool.MCPDiscoveredTool")

/// A wrapper that makes an MCP tool definition conform to the `Tool` protocol.
///
/// This allows MCP tools to be used seamlessly with the AnyLanguageModel framework.
struct MCPDiscoveredTool: Tool, @unchecked Sendable {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let definition: MCPToolDefinition
    private let transport: any MCPTransport

    init(definition: MCPToolDefinition, transport: any MCPTransport) {
        self.definition = definition
        self.transport = transport
    }

    var name: String {
        definition.name
    }

    var description: String {
        definition.description ?? "No description available"
    }

    var parameters: GenerationSchema {
        definition.toGenerationSchema()
    }

    nonisolated func call(arguments: GeneratedContent) async throws -> String {
        logger.debug("Calling MCP tool", metadata: ["toolName": "\(definition.name)"])

        // Convert GeneratedContent to dictionary
        let argsDict = try convertToArgumentsDictionary(arguments)

        // Call the tool via transport (this crosses actor boundary safely)
        let result = try await transport.callTool(name: definition.name, arguments: argsDict)

        logger.debug(
            "MCP tool returned",
            metadata: [
                "toolName": "\(definition.name)",
                "contentCount": "\(result.content.count)",
                "isError": "\(result.isError ?? false)",
            ]
        )

        // Convert MCP response to String
        let output = try convertToString(result)
        logger.debug(
            "MCP tool output",
            metadata: [
                "toolName": "\(definition.name)",
                "outputLength": "\(output.count)",
            ]
        )
        return output
    }

    // MARK: - Private Helpers

    /// Converts GeneratedContent to [String: Any] dictionary
    nonisolated private func convertToArgumentsDictionary(_ content: GeneratedContent) throws -> [String: Any] {
        guard case .structure(let properties, _) = content.kind else {
            throw MCPError.invalidResponse
        }

        var dict: [String: Any] = [:]
        for (key, value) in properties {
            dict[key] = try convertContentToAny(value)
        }
        return dict
    }

    /// Converts GeneratedContent to Any
    nonisolated private func convertContentToAny(_ content: GeneratedContent) throws -> Any {
        switch content.kind {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return try values.map { try convertContentToAny($0) }
        case .structure(let properties, _):
            var dict: [String: Any] = [:]
            for (key, value) in properties {
                dict[key] = try convertContentToAny(value)
            }
            return dict
        }
    }

    /// Converts MCP tool result to String.
    nonisolated private func convertToString(_ result: MCPCallToolResult) throws -> String {
        // Check if result is an error
        let isError = result.isError ?? false
        if isError {
            logger.error(
                "MCP tool returned error",
                metadata: [
                    "toolName": "\(definition.name)",
                    "content": "\(result.content)",
                ]
            )
            throw MCPError.toolExecutionError("Tool execution failed")
        }

        // Collect all text parts
        var textParts: [String] = []

        for content in result.content {
            switch content.type {
            case "text":
                if let text = content.text {
                    textParts.append(text)
                }

            case "image":
                if let mimeType = content.mimeType {
                    textParts.append("[Image: \(mimeType)]")
                }

            case "resource":
                if let text = content.text {
                    textParts.append(text)
                }

            default:
                if let text = content.text {
                    textParts.append(text)
                }
            }
        }

        // If no parts were successfully converted, throw error
        if textParts.isEmpty {
            logger.warning("No text content in MCP tool result", metadata: ["toolName": "\(definition.name)"])
            throw MCPError.invalidResponse
        }

        // Join all text parts
        return textParts.joined(separator: "\n")
    }
}
