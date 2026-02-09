# Swift Agent

A Swift-native agent runtime focused on model-tool orchestration, MCP integration, session persistence, and hookable execution.

## What it provides

- `AgentCenter` actor runtime (`LiveAgentCenter`) for:
  - registering agents, models, tools, MCP server configs, and hooks
  - creating sessions
  - running agents (structured output or plain text)
  - streaming responses
- Session/run persistence via `AgentStorage`:
  - `InMemoryAgentStorage`
  - `FileAgentStorage`
- Hook system:
  - pre-hooks (input validation/transformation)
  - post-hooks (analytics/side effects)
  - blocking and non-blocking modes
- Event observer system for runtime telemetry

## Package layout

- Core library: `Sources/Core`
- CLI app: `Sources/CLI`
- Example app: `Sources/Example`
- Tests: `Tests/SwiftAgentCoreTests`

## Quick start

```swift
import AnyLanguageModel
import SwiftAgentCore

let center = LiveAgentCenter()

// Register a model
await center.register(model: myModel, named: "gpt-4")

// Register an agent (ID auto-generated)
let agent = Agent(
    name: "CodeReviewer",
    description: "Reviews code and suggests improvements",
    modelName: "gpt-4",
    instructions: "You are an expert code reviewer."
)
await center.register(agent: agent)

// Create session
let session = try await center.createSession(
    agentId: agent.id,
    userId: UUID(),
    name: "Review Session"
)

let context = AgentSessionContext(
    agentId: agent.id,
    userId: session.userId,
    sessionId: session.id
)

// Run as String (convenience overload)
let run = try await center.runAgent(
    session: context,
    message: "Review this Swift snippet"
)

print(try run.asString())
```

## Structured output

```swift
@Generable
struct ReviewSummary: Codable {
    @Guide(description: "Overall score 1-10", .range(1...10))
    var score: Int

    @Guide(description: "Short summary")
    var summary: String
}

let run = try await center.runAgent(
    session: context,
    message: "Review this pull request",
    as: ReviewSummary.self
)

let summary = try run.decoded(as: ReviewSummary.self)
```

## Configuration loading

You can load model/agent/MCP definitions from `AgentConfiguration`:

```swift
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
            id: "code-reviewer",
            name: "Code Reviewer",
            description: "Reviews code",
            modelName: "gpt-4",
            instructions: "Be concise and precise."
        )
    ],
    mcpServers: []
)

try await center.load(configuration: config)
```

## Hooks

Register hooks and reference them by name from an agent:

```swift
let pre = RegisteredPreHook(name: "validate", blocking: true) { context in
    guard !context.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw NSError(domain: "Validation", code: 1)
    }
}

await center.register(preHook: pre)
```

## Streaming

```swift
let stream = await center.streamAgent(session: context, message: "Explain actors in Swift")
for try await chunk in stream {
    print(chunk)
}
```

## Running

```bash
swift run swift-agent-example
swift run swift-agent-cli --help
swift test
```

## Notes

- `Run.asString()` throws if payload data is not valid UTF-8.
- Missing model registrations now fail with `AgentError.modelNotFound` instead of crashing.
- API keys are plain strings in `AgentModel`; prefer environment/secret management for production.
