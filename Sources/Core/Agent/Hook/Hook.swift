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
