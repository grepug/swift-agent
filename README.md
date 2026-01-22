# Swift Agent - Minimal Implementation

A minimal, Agno-inspired agent framework in Swift that implements the core agent-model-tool execution loop.

## Architecture

Inspired by [Agno](https://agno.com), this implementation provides:

### Core Components

#### 1. **Agent** ([Agent.swift](Sources/SwiftAgentCore/Agent.swift))

The central orchestrator that manages:

- System instructions
- Model interactions
- Tool execution
- Conversation storage
- The agent-model-tool loop

#### 2. **Model Protocol** ([Model.swift](Sources/SwiftAgentCore/Model.swift))

Abstract interface for language models:

```swift
protocol ModelProtocol: Sendable {
    func generate(messages: [Message]) async throws -> ModelResponse
}
```

#### 3. **Tool System**

- **ToolProtocol** ([ToolProtocol.swift](Sources/SwiftAgentCore/Tool/ToolProtocol.swift)): Interface for executable tools
- **ToolCall** ([ToolCall.swift](Sources/SwiftAgentCore/Tool/ToolCall.swift)): Represents tool invocations and results

#### 4. **Message System** ([Message.swift](Sources/SwiftAgentCore/Agent/Message.swift))

Conversation representation with roles:

- `system`: Instructions
- `user`: User input
- `assistant`: Model responses
- `tool`: Tool execution results

#### 5. **Storage** ([StorageProtocol.swift](Sources/SwiftAgentCore/Storage/StorageProtocol.swift))

Persistence layer for:

- Run history
- Session state
- Includes `InMemoryStorage` implementation

## Execution Flow

```
1. Agent receives user message
2. Builds context (system instructions + history + user message)
3. Sends to model
4. Model responds with either:
   a. Tool calls → Execute tools → Go to step 3
   b. Final message → Return to caller
5. Save run to storage
```

## Usage

```swift
import SwiftAgentCore

// Create a model (mock or real LLM)
let model = MockModel(responses: ["Hello!"])

// Create an agent
let agent = Agent(
    name: "My Agent",
    model: model,
    instructions: ["You are a helpful assistant."],
    tools: [CalculatorTool()]
)

// Run the agent
let run = try await agent.run(message: "Hello!")
print(run.content ?? "")
```

## File Structure

```
Sources/
├── SwiftAgentCore/
│   ├── Agent.swift           # Main agent logic
│   ├── Model.swift           # Model protocol
│   ├── AnyCodable.swift      # Type-erased codable helper
│   ├── Mocks.swift           # Mock implementations
│   ├── Agent/
│   │   ├── Message.swift     # Message types
│   │   ├── Run.swift         # Run results
│   │   ├── Session.swift     # Session metadata
│   │   └── ModelResponse.swift
│   ├── Tool/
│   │   ├── ToolProtocol.swift
│   │   └── ToolCall.swift
│   └── Storage/
│       └── StorageProtocol.swift
└── Example/
    └── main.swift            # Demo application
```

## Running the Example

```bash
swift run swift-agent-example
```

## Next Steps

To make this production-ready:

1. **Integrate Real LLM Provider**
   - Implement `ModelProtocol` for OpenAI, Anthropic, or local models
   - Add API key management
   - Handle streaming responses

2. **Add Persistent Storage**
   - Implement `StorageProtocol` with SQLite, PostgreSQL, or file-based storage
   - Add conversation history loading

3. **Enhanced Tool System**
   - JSON schema validation
   - Tool discovery and registration
   - Parallel tool execution

4. **Error Handling**
   - Retry logic for API failures
   - Graceful degradation
   - Better error messages

5. **Advanced Features**
   - Streaming responses
   - Structured output (Pydantic-style)
   - Memory systems
   - Multi-agent coordination

## License

MIT
