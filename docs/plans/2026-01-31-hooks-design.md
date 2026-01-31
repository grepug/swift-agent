# Agent Hooks Design

**Date**: 2026-01-31  
**Status**: Implementation  
**Inspired by**: [Agno Pre-hooks and Post-hooks](https://docs.agno.com/hooks/overview)

## Overview

Add pre-hooks and post-hooks support to Swift Agent framework, allowing custom logic execution before and after agent runs. This enables use cases like logging, validation, monitoring, guardrails, and data preprocessing/postprocessing.

## Design Goals

1. **Simple and Flexible** - Function-based hooks like Agno, not complex protocols
2. **Non-blocking Support** - Distinguish blocking vs non-blocking hooks
3. **Configurable** - Hook names in Agent config, registered in AgentCenter
4. **Type-safe** - Separate PreHook and PostHook with appropriate parameters
5. **Lifecycle Management** - Proper task management for background hooks

## Architecture

### 1. Core Types

#### Hook Configuration
```swift
// Serializable hook metadata
public struct Hook: Sendable, Codable, Hashable {
    public let name: String
    public let blocking: Bool  // true = wait for completion, false = fire-and-forget
    
    public init(name: String, blocking: Bool = true)
}
```

#### Hook Functions
```swift
// Pre-hook: runs before agent execution
public typealias PreHookFunction = @Sendable (HookContext) async throws -> Void

// Post-hook: runs after agent execution
public typealias PostHookFunction = @Sendable (HookContext, Run) async throws -> Void
```

#### Registered Hooks
```swift
// Combines config with executable function
public struct RegisteredPreHook: Sendable {
    public let config: Hook
    public let execute: PreHookFunction
}

public struct RegisteredPostHook: Sendable {
    public let config: Hook
    public let execute: PostHookFunction
}
```

#### Hook Context
```swift
public struct HookContext: Sendable {
    public let agent: Agent
    public let session: AgentSessionContext
    public let userMessage: String
    public var metadata: [String: AnyCodable]  // For passing data between hooks
}
```

### 2. Agent Configuration

```swift
public struct Agent: Sendable, Codable, Hashable {
    // Existing fields...
    package let preHookNames: [String]
    package let postHookNames: [String]
    
    public init(
        id: String,
        name: String,
        description: String,
        modelName: String,
        instructions: String,
        toolNames: [String] = [],
        mcpServerNames: [String] = [],
        preHookNames: [String] = [],   // NEW
        postHookNames: [String] = []   // NEW
    )
}
```

### 3. AgentCenter Protocol

```swift
public protocol AgentCenter: Sendable {
    // Existing methods...
    
    // Hook management
    func register(preHook: RegisteredPreHook) async
    func register(postHook: RegisteredPostHook) async
    func preHook(named name: String) async -> RegisteredPreHook?
    func postHook(named name: String) async -> RegisteredPostHook?
}
```

### 4. LiveAgentCenter Implementation

```swift
actor LiveAgentCenter: AgentCenter {
    private var agents: [String: Agent] = [:]
    private var models: [String: any LanguageModel] = [:]
    private var tools: [String: any Tool] = [:]
    
    // Hook storage
    private var preHooks: [String: RegisteredPreHook] = [:]
    private var postHooks: [String: RegisteredPostHook] = [:]
    
    // Background task management
    private var backgroundHookTasks: [UUID: Task<Void, Never>] = [:]
}
```

## Execution Flow

```
1. Load agent configuration
2. Build HookContext
3. Execute BLOCKING pre-hooks (sequential, await each)
4. Launch NON-BLOCKING pre-hooks (fire-and-forget Tasks)
5. Execute agent (existing logic)
6. Execute BLOCKING post-hooks (sequential, await each)
7. Launch NON-BLOCKING post-hooks (fire-and-forget Tasks)
8. Return run result (don't wait for non-blocking hooks)
```

### Blocking Hooks
- Execute sequentially in the order defined
- Await completion before proceeding
- Errors propagate to caller
- Used for: validation, guardrails, required preprocessing

### Non-blocking Hooks
- Create independent top-level Tasks
- Return immediately without waiting
- Errors logged but don't affect main flow
- Tasks tracked in `backgroundHookTasks` for lifecycle management
- Auto-cleanup when completed
- Used for: logging, analytics, notifications

## Implementation Details

### Pre-hook Execution
```swift
let preHooks = agent.preHookNames.compactMap { preHooks[$0] }
let blockingPreHooks = preHooks.filter { $0.config.blocking }
let nonBlockingPreHooks = preHooks.filter { !$0.config.blocking }

// Blocking: sequential execution
for hook in blockingPreHooks {
    try await hook.execute(hookContext)
}

// Non-blocking: fire-and-forget
for hook in nonBlockingPreHooks {
    executeNonBlockingHook(hook) { hook in
        try await hook.execute(hookContext)
    }
}
```

### Background Task Management
```swift
private func executeNonBlockingHook<H>(
    _ hook: H,
    execute: @Sendable @escaping (H) async throws -> Void
) where H: Sendable {
    let taskId = UUID()
    let task = Task {
        do {
            try await execute(hook)
        } catch {
            logger.warning("Non-blocking hook failed", metadata: [
                "hook.name": .string(hookName),
                "error": .string(String(describing: error))
            ])
        }
        await self.removeBackgroundTask(taskId)
    }
    backgroundHookTasks[taskId] = task
}

private func removeBackgroundTask(_ id: UUID) {
    backgroundHookTasks.removeValue(forKey: id)
}
```

### Lifecycle Management
```swift
// For graceful shutdown
func waitForBackgroundHooks() async {
    await withTaskGroup(of: Void.self) { group in
        for task in backgroundHookTasks.values {
            group.addTask { await task.value }
        }
    }
}

// For immediate cancellation
func cancelBackgroundHooks() {
    for task in backgroundHookTasks.values {
        task.cancel()
    }
    backgroundHookTasks.removeAll()
}
```

## Usage Example

```swift
// Define hooks
let loggingPreHook = RegisteredPreHook(
    config: Hook(name: "request-logger", blocking: false)
) { context in
    print("[Pre] Agent \(context.agent.name) - Message: \(context.userMessage)")
}

let loggingPostHook = RegisteredPostHook(
    config: Hook(name: "response-logger", blocking: false)
) { context, run in
    print("[Post] Agent \(context.agent.name) - Duration: \(run.duration)s")
}

let validationPreHook = RegisteredPreHook(
    config: Hook(name: "input-validator", blocking: true)
) { context in
    guard !context.userMessage.isEmpty else {
        throw AgentError.invalidInput("Message cannot be empty")
    }
}

// Register hooks
await agentCenter.register(preHook: loggingPreHook)
await agentCenter.register(preHook: validationPreHook)
await agentCenter.register(postHook: loggingPostHook)

// Configure agent
let agent = Agent(
    id: "assistant",
    name: "Assistant",
    description: "Helpful assistant",
    modelName: "gpt-4",
    instructions: "You are a helpful assistant",
    preHookNames: ["input-validator", "request-logger"],
    postHookNames: ["response-logger"]
)

await agentCenter.register(agent: agent)

// Run agent - hooks execute automatically
let run = try await agentCenter.runAgent(
    session: session,
    message: "Hello!",
    as: String.self,
    loadHistory: true
)
// input-validator runs (blocking) - waits
// request-logger launches (non-blocking) - returns immediately
// agent executes
// response-logger launches (non-blocking) - returns immediately
// run returned (logger still running in background)
```

## File Structure

```
Sources/Core/Agent/Hook/
  ├── Hook.swift              # Hook, RegisteredPreHook, RegisteredPostHook
  └── HookContext.swift       # HookContext

Sources/Core/Agent/
  └── Agent.swift             # Add preHookNames, postHookNames

Sources/Core/AgentCenter/
  ├── AgentCenterProtocol.swift   # Add hook management methods
  └── LiveAgentCenter.swift       # Implement hook execution logic

Tests/SwiftAgentCoreTests/
  └── HooksTests.swift        # Test blocking/non-blocking hooks
```

## Testing Strategy

1. **Blocking Pre-hook Tests**
   - Verify sequential execution order
   - Test error propagation
   - Confirm agent waits for completion

2. **Non-blocking Pre-hook Tests**
   - Verify immediate return
   - Test background execution
   - Confirm errors don't affect agent

3. **Blocking Post-hook Tests**
   - Verify execution after agent completes
   - Test error handling
   - Confirm run waits for completion

4. **Non-blocking Post-hook Tests**
   - Verify fire-and-forget behavior
   - Test background execution
   - Confirm errors logged only

5. **Hook Context Tests**
   - Verify correct context passed
   - Test metadata passing between hooks

6. **Task Lifecycle Tests**
   - Verify task cleanup
   - Test graceful shutdown
   - Test cancellation

## Migration Notes

- Existing agents continue to work (empty hook arrays by default)
- No breaking changes to Agent initialization
- Follows existing pattern: toolNames, mcpServerNames, hookNames
- Compatible with AgentConfiguration JSON loading

## Future Enhancements

- Hook priority/ordering control
- Conditional hook execution (e.g., only on errors)
- Hook composition (chain multiple hooks)
- Built-in hooks library (rate limiting, PII detection, etc.)
- Streaming hooks (for streamAgent)
- Hook metrics and observability
