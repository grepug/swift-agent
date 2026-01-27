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

### Basic Programmatic Usage

```swift
import SwiftAgentCore
import AnyLanguageModel

// 1. Set up the agent center
@Dependency(\.agentCenter) var agentCenter

// 2. Register models
await agentCenter.register(model: myOpenAIModel, named: "gpt-4")
await agentCenter.register(model: myClaudeModel, named: "claude-3-sonnet")

// 3. Register native Swift tools (optional)
await agentCenter.register(tool: SearchTool())
await agentCenter.register(tool: FileReaderTool())

// 4. Create and register an agent
let agent = Agent(
    name: "CodeReviewer",
    description: "Reviews code and suggests improvements",
    modelName: "gpt-4",
    instructions: "You are an expert code reviewer.",
    toolNames: ["search-tool"],
    mcpServerNames: ["filesystem"]
)
await agentCenter.register(agent: agent)

// 5. Run the agent
let session = AgentSessionContext(
    agentId: agent.id,
    userId: UUID()
)
let run = try await agentCenter.runAgent(
    session: session,
    message: "Review this Swift code...",
    as: String.self,
    loadHistory: true
)
```

### Loading from Configuration

You can load models, agents, and MCP servers from a configuration object. Models defined in the config will be automatically registered as OpenAI-compatible language models.

#### Option 1: Load from JSON File

```swift
import SwiftAgentCore
import AnyLanguageModel

// 1. Create the agent center
let agentCenter = LiveAgentCenter()

// 2. Optionally register native Swift tools (if any are referenced in the config)
await agentCenter.register(tool: SearchTool())
await agentCenter.register(tool: FileReaderTool())

// 3. Load configuration from JSON file (includes models, agents, and MCP servers)
let configURL = URL(fileURLWithPath: "agent-config.json")
let data = try Data(contentsOf: configURL)
let config = try JSONDecoder().decode(AgentConfiguration.self, from: data)
try await agentCenter.load(configuration: config)

// 4. Use the agents defined in the config
let agent = await agentCenter.agent(id: myAgentId)
```

#### Option 2: Hardcode Configuration

```swift
import SwiftAgentCore
import AnyLanguageModel

// 1. Create the agent center
let agentCenter = LiveAgentCenter()

// 2. Create configuration programmatically
let config = AgentConfiguration(
    models: [
        AgentModel(
            name: "gpt-4",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            id: "gpt-4",
            apiKey: "sk-..."
        )
    ],
    agents: [
        Agent(
            name: "CodeReviewer",
            description: "Reviews code",
            modelName: "gpt-4",
            instructions: "You are an expert code reviewer.",
            toolNames: [],
            mcpServerNames: ["filesystem"]
        )
    ],
    mcpServers: [
        MCPServerConfiguration(
            name: "filesystem",
            transport: .stdio(
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", "/path"],
                env: [:]
            )
        )
    ]
)

// 3. Load the configuration
try await agentCenter.load(configuration: config)
```

**Example Configuration File** (`agent-config.json`):

```json
{
  "models": [
    {
      "name": "gpt-4",
      "baseURL": "https://api.openai.com/v1",
      "id": "gpt-4",
      "apiKey": "sk-your-api-key-here"
    },
    {
      "name": "claude-3-sonnet",
      "baseURL": "https://api.anthropic.com/v1",
      "id": "claude-3-sonnet-20240229",
      "apiKey": "sk-ant-your-api-key-here"
    }
  ],
  "agents": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "CodeReviewer",
      "description": "Reviews code and suggests improvements",
      "modelName": "gpt-4",
      "instructions": "You are an expert code reviewer.",
      "toolNames": ["search-tool"],
      "mcpServerNames": ["filesystem"]
    }
  ],
  "mcpServers": [
    {
      "name": "filesystem",
      "transport": {
        "type": "stdio",
        "command": "npx",
        "args": [
          "-y",
          "@modelcontextprotocol/server-filesystem",
          "/path/to/dir"
        ],
        "env": {}
      }
    }
  ]
}
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
