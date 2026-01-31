---
description: "A CLI-based agent framework for managing conversational AI agents with persistent sessions, tool execution, and multi-agent interactions."
tools: ["execute"]
---

# Swift Agent CLI

A command-line interface for managing and interacting with context-aware AI agents built on the Swift Agent framework.

## Purpose

This agent enables you to:

- **Create and manage persistent conversation sessions** with AI agents
- **Chat with agents** that maintain full conversation history and context
- **Execute multi-agent workflows** where agents can interact with each other
- **Leverage tool execution** including MCP (Model Context Protocol) servers
- **Track and review session history** across multiple conversations

## When to Use

Use this agent when you need to:

1. **Build conversational AI applications** with persistent state
2. **Test agent behaviors** and multi-agent interactions
3. **Develop agents that use external tools** (calculators, web browsers, APIs, etc.)
4. **Create agent-to-agent communication** workflows (like TestAgent chatting with ChatAgent)
5. **Manage long-running conversations** that span multiple interactions

## Core Commands

### Session Management

#### `session create`

Creates a new persistent conversation session.

**Inputs:**

- `--agent-id`: ID of the agent to use (default: "chat")
- `--user-id`: Optional UUID for the user
- `--name`: Optional friendly name for the session

**Output:** Session UUID and metadata

#### `session list`

Lists all existing sessions with filtering options.

**Inputs:**

- `--agent-id`: Filter sessions by agent
- `--format`: Output format (table, json, csv)

**Output:** Formatted list of sessions with IDs, agent names, and timestamps

#### `session chat`

Sends a message to an existing session and receives the agent's response.

**Inputs:**

- `message`: The message to send (required argument)
- `--session-id`: UUID of the session (required)
- `--agent-id`: ID of the agent (default: "chat")

**Output:** Agent's response with run metadata

#### `session delete`

Deletes a session and its history.

**Inputs:**

- `--session-id`: UUID of the session to delete

## Agent Capabilities

The framework supports agents with:

### Tool Integration

- Native Swift tools (custom implementations)
- MCP (Model Context Protocol) servers for external tool access
- Automatic tool discovery and invocation

### Session Persistence

- Full conversation history storage
- Message tracking (user, assistant, system, tool messages)
- Tool call and result preservation
- Run-level tracking with metrics

### Multi-Agent Communication

Example: TestAgent can chat with ChatAgent by executing CLI commands through a CommandTool, enabling agent-to-agent conversations.

## Example Workflows

**Important:** Always create a new session before starting any conversation. Each interaction should begin with `session create` to establish proper context and persistence.

### 1. Single Agent Chat

```bash
# Create a session
swift run swift-agent-cli session create --agent-id=chat --name="My Chat"

# Chat with the session
swift run swift-agent-cli session chat --session-id=<UUID> "Tell me about Swift"

# View all sessions
swift run swift-agent-cli session list
```

### 2. Multi-Agent Interaction

```bash
# Create a test agent session
swift run swift-agent-cli session create --agent-id=test

# Start agent-to-agent conversation
swift run swift-agent-cli session chat --session-id=<UUID> --agent-id=test \
  "start the conversation with Chat Agent with the topic of travelling to Chengdu"
```

## Constraints & Limitations

### Will NOT:

- Execute commands without proper session context
- Allow direct access to file system without appropriate tools
- Persist data outside the configured storage directory
- Execute arbitrary code without tool definitions

### Requires:

- Valid session IDs for chat operations
- Configured agents with proper model connections
- Storage backend (file-based or custom)
- Language model API credentials (for agent execution)

## Configuration

Agents are configured programmatically or via configuration files with:

- Model selection and credentials
- System instructions
- Available tools
- MCP server connections

## Progress & Feedback

The CLI provides:

- ✅ Success indicators for operations
- ❌ Error messages with clear descriptions
- 💬 Session metadata display
- 📤 Message sent indicators
- 🤖 Agent response formatting
- Run IDs for tracking and debugging

## Storage

Sessions and messages are persisted to:

- Default: `.data/` directory in workspace
- Configurable via environment: `SWIFT_AGENT_STORAGE_DIR`
- JSON format for human readability
- Hierarchical structure: `agents/{agentId}/sessions/{sessionId}/`

## Integration Points

Works with:

- AnyLanguageModel framework for model abstraction
- MCP servers for external tool integration
- Custom Swift tools for specialized operations
- File-based or custom storage backends

## Error Handling

Gracefully handles:

- Invalid session IDs (displays error, doesn't crash)
- Missing agents (validation before execution)
- Tool execution failures (captures and reports)
- Network issues (from model APIs)
- Storage errors (clear error messages)

---

**Built on:** Swift Agent Framework (Agno-inspired architecture)
**Platform:** macOS, iOS (via SwiftAgentCore library)
**CLI Tool:** `swift-agent-cli`
