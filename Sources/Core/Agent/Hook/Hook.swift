import Foundation

// MARK: - Hook Configuration

/// Hook configuration - serializable metadata
public struct Hook: Sendable, Codable, Hashable {
    /// Unique name for the hook
    public let name: String

    /// Whether the hook should block agent execution
    /// - true: Wait for hook completion before proceeding (for validation, guardrails)
    /// - false: Fire-and-forget background execution (for logging, analytics)
    public let blocking: Bool

    public init(name: String, blocking: Bool = true) {
        self.name = name
        self.blocking = blocking
    }
}

// MARK: - Hook Functions

/// Pre-hook function signature
/// Executes before agent run with access to the hook context
/// Can modify context.userMessage to transform the input
/// Note: Only blocking pre-hooks can modify the message (non-blocking hooks receive a copy)
public typealias PreHookFunction = @Sendable (inout HookContext) async throws -> Void

/// Post-hook function signature
/// Executes after agent run with access to context and the generated run
public typealias PostHookFunction = @Sendable (HookContext, Run) async throws -> Void

/// Summary-hook function signature.
/// Executes when context-window compaction drops history and a new summary is needed.
/// Return `nil` to keep existing summary unchanged.
public typealias SummaryHookFunction = @Sendable (SummaryHookContext) async throws -> String?

// MARK: - Registered Hooks

/// A pre-hook registered in the agent center with its executable function
public struct RegisteredPreHook: Sendable {
    /// Hook configuration
    public let config: Hook

    /// Executable function
    public let execute: PreHookFunction

    public init(config: Hook, execute: @escaping PreHookFunction) {
        self.config = config
        self.execute = execute
    }

    /// Convenience initializer with name and blocking flag
    public init(
        name: String,
        blocking: Bool = true,
        execute: @escaping PreHookFunction
    ) {
        self.config = Hook(name: name, blocking: blocking)
        self.execute = execute
    }
}

/// A post-hook registered in the agent center with its executable function
public struct RegisteredPostHook: Sendable {
    /// Hook configuration
    public let config: Hook

    /// Executable function
    public let execute: PostHookFunction

    public init(config: Hook, execute: @escaping PostHookFunction) {
        self.config = config
        self.execute = execute
    }

    /// Convenience initializer with name and blocking flag
    public init(
        name: String,
        blocking: Bool = true,
        execute: @escaping PostHookFunction
    ) {
        self.config = Hook(name: name, blocking: blocking)
        self.execute = execute
    }
}

/// Context provided to summary hooks during context-window compaction.
public struct SummaryHookContext: Sendable {
    /// The agent being executed.
    public let agent: Agent

    /// The session context for this run.
    public let session: AgentSessionContext

    /// The current persisted session summary, if any.
    public let existingSummary: String?

    /// Messages dropped by context-window trimming.
    public let droppedMessages: [Message]

    /// Messages retained in the trimmed history.
    public let retainedMessages: [Message]

    /// Active history message cap.
    public let maxHistoryMessages: Int?

    /// Active history token cap.
    public let maxHistoryTokens: Int?

    public init(
        agent: Agent,
        session: AgentSessionContext,
        existingSummary: String?,
        droppedMessages: [Message],
        retainedMessages: [Message],
        maxHistoryMessages: Int?,
        maxHistoryTokens: Int?
    ) {
        self.agent = agent
        self.session = session
        self.existingSummary = existingSummary
        self.droppedMessages = droppedMessages
        self.retainedMessages = retainedMessages
        self.maxHistoryMessages = maxHistoryMessages
        self.maxHistoryTokens = maxHistoryTokens
    }
}

/// A summary hook registered in the agent center.
public struct RegisteredSummaryHook: Sendable {
    /// Unique hook name.
    public let name: String

    /// Executable function.
    public let execute: SummaryHookFunction

    public init(name: String, execute: @escaping SummaryHookFunction) {
        self.name = name
        self.execute = execute
    }
}
