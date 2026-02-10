import Foundation

/// Runtime policy controls for a single agent execution.
public struct ExecutionPolicy: Sendable, Codable, Hashable {
    /// Maximum wall-clock time in seconds for a single execution attempt.
    ///
    /// `nil` means no timeout.
    public var timeout: TimeInterval?

    /// Number of retries after the initial attempt fails.
    ///
    /// For example, `retries = 2` means up to 3 total attempts.
    public var retries: Int

    /// Whether cancellation should immediately terminate execution.
    public var propagateCancellation: Bool

    /// Maximum number of tool calls the model may perform in one response.
    ///
    /// Currently mapped to OpenAI Responses API custom options when supported.
    public var maxToolCalls: Int?

    /// Maximum number of history messages loaded into the transcript before the new user prompt.
    ///
    /// `nil` means no message-count cap.
    public var maxHistoryMessages: Int?

    /// Approximate maximum number of history tokens loaded into the transcript before the new user prompt.
    ///
    /// Token counting uses a lightweight estimate based on text length.
    /// `nil` means no token cap.
    public var maxHistoryTokens: Int?

    /// Optional summary-hook name used when history is compacted.
    ///
    /// If set and history is trimmed, the registered summary hook can generate a new session summary.
    public var summaryHookName: String?

    public init(
        timeout: TimeInterval? = nil,
        retries: Int = 0,
        propagateCancellation: Bool = true,
        maxToolCalls: Int? = nil,
        maxHistoryMessages: Int? = nil,
        maxHistoryTokens: Int? = nil,
        summaryHookName: String? = nil
    ) {
        self.timeout = timeout
        self.retries = max(0, retries)
        self.propagateCancellation = propagateCancellation
        self.maxToolCalls = maxToolCalls
        self.maxHistoryMessages = maxHistoryMessages
        self.maxHistoryTokens = maxHistoryTokens
        self.summaryHookName = summaryHookName
    }

    public static let `default` = ExecutionPolicy()
}
