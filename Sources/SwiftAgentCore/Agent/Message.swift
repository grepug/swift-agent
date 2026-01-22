import Foundation

/// Represents the role of a message in the conversation
public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

/// Represents a message in the agent conversation
public struct Message: Sendable, Codable, Identifiable {
    public let id: UUID
    public let role: MessageRole
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    public let name: String?
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        name: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
        self.createdAt = createdAt
    }
}

extension Message {
    /// Creates a system message
    public static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }
    
    /// Creates a user message
    public static func user(_ content: String) -> Message {
        Message(role: .user, content: content)
    }
    
    /// Creates an assistant message
    public static func assistant(_ content: String) -> Message {
        Message(role: .assistant, content: content)
    }
    
    /// Creates an assistant message with tool calls
    public static func assistantWithTools(_ toolCalls: [ToolCall]) -> Message {
        Message(role: .assistant, toolCalls: toolCalls)
    }
    
    /// Creates a tool result message
    public static func tool(content: String, toolCallId: String, name: String) -> Message {
        Message(role: .tool, content: content, toolCallId: toolCallId, name: name)
    }
}
