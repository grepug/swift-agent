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

    public init(
        timeout: TimeInterval? = nil,
        retries: Int = 0,
        propagateCancellation: Bool = true,
        maxToolCalls: Int? = nil
    ) {
        self.timeout = timeout
        self.retries = max(0, retries)
        self.propagateCancellation = propagateCancellation
        self.maxToolCalls = maxToolCalls
    }

    public static let `default` = ExecutionPolicy()
}

