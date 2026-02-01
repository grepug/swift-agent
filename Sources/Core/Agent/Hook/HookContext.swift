import Foundation

/// Context provided to hooks during agent execution
public struct HookContext: Sendable {
    /// The agent being executed
    public let agent: Agent

    /// The session context for this run
    public let session: AgentSessionContext

    /// The user message triggering this run
    /// Pre-hooks can modify this to transform the input before it reaches the agent
    public var userMessage: String

    /// Additional metadata that can be passed between hooks
    /// Use this to share data across multiple hooks in the same run
    public var metadata: [String: AnyCodable]

    public init(
        agent: Agent,
        session: AgentSessionContext,
        userMessage: String,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.agent = agent
        self.session = session
        self.userMessage = userMessage
        self.metadata = metadata
    }
}
