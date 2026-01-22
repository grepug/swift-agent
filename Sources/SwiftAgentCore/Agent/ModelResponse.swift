import Foundation

/// Represents a response from the model
public struct ModelResponse: Sendable {
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let finishReason: FinishReason
    
    public init(
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        finishReason: FinishReason = .stop
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.finishReason = finishReason
    }
}

/// Represents why the model stopped generating
public enum FinishReason: String, Sendable {
    case stop
    case toolCalls = "tool_calls"
    case length
    case contentFilter = "content_filter"
}
