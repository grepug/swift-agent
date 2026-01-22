import Foundation

/// The core agent that orchestrates model interactions and tool execution
public struct Agent: Sendable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let sessionId: UUID
    public let userId: UUID

    public let model: ModelProtocol
    public let storage: StorageProtocol
    public let instructions: [String]
    public let tools: [ToolProtocol]

    public init(
        id: UUID = UUID(),
        name: String = "Default Agent",
        description: String? = nil,
        sessionId: UUID = UUID(),
        userId: UUID = UUID(),
        model: ModelProtocol,
        storage: StorageProtocol = InMemoryStorage(),
        instructions: [String],
        tools: [ToolProtocol] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sessionId = sessionId
        self.userId = userId
        self.model = model
        self.storage = storage
        self.instructions = instructions
        self.tools = tools
    }
}

// MARK: - Agent Execution

extension Agent {
    /// Run the agent with a user message
    /// - Parameter message: The user's input message
    /// - Returns: The run result containing all messages and the final response
    public func run(message: String) async throws -> Run {
        var messages: [Message] = []
        
        // 1. Add system instructions
        if !instructions.isEmpty {
            messages.append(.system(instructions.joined(separator: "\n")))
        }
        
        // 2. TODO: Load conversation history from storage if needed
        
        // 3. Add user message
        messages.append(.user(message))
        
        // 4. Execute the agent-model-tool loop
        let maxIterations = 10
        var iterations = 0
        
        while iterations < maxIterations {
            iterations += 1
            
            // Call the model
            let response = try await model.generate(messages: messages)
            
            // Check if model wants to call tools
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                // Add assistant message with tool calls
                messages.append(.assistantWithTools(toolCalls))
                
                // Execute each tool call
                for toolCall in toolCalls {
                    let result = await executeToolCall(toolCall)
                    messages.append(.tool(
                        content: result.content,
                        toolCallId: result.toolCallId,
                        name: toolCall.name
                    ))
                }
            } else {
                // Model returned a final response
                if let content = response.content {
                    messages.append(.assistant(content))
                }
                break
            }
        }
        
        // 5. Create run record
        let run = Run(
            agentId: id,
            sessionId: sessionId,
            userId: userId,
            messages: messages,
            content: messages.last?.content
        )
        
        // 6. Save to storage
        try await storage.append(run, for: self)
        
        return run
    }
    
    /// Execute a single tool call
    private func executeToolCall(_ toolCall: ToolCall) async -> ToolResult {
        // Find the tool
        guard let tool = tools.first(where: { $0.name == toolCall.name }) else {
            return ToolResult(
                toolCallId: toolCall.id,
                content: "Error: Tool '\(toolCall.name)' not found",
                isError: true
            )
        }
        
        // Execute the tool
        do {
            let result = try await tool.execute(arguments: toolCall.arguments)
            return ToolResult(
                toolCallId: toolCall.id,
                content: result
            )
        } catch {
            return ToolResult(
                toolCallId: toolCall.id,
                content: "Error executing tool: \(error.localizedDescription)",
                isError: true
            )
        }
    }
}

// MARK: - Agent Errors

public enum AgentError: Error, CustomStringConvertible {
    case maxIterationsReached
    case noResponseFromModel
    case invalidConfiguration(String)
    
    public var description: String {
        switch self {
        case .maxIterationsReached:
            return "Maximum iterations reached in agent loop"
        case .noResponseFromModel:
            return "No response received from model"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}
