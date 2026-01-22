import Foundation

/// Represents a request from the model to call a tool
public struct ToolCall: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: String
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        arguments: String
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Represents the result of a tool execution
public struct ToolResult: Sendable {
    public let toolCallId: String
    public let content: String
    public let isError: Bool
    
    public init(
        toolCallId: String,
        content: String,
        isError: Bool = false
    ) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}
