import Foundation

/// Represents token usage information from a language model response.
///
/// Token usage helps track API costs and manage rate limits.
public struct TokenUsage: Sendable, Codable, Hashable {
    /// Number of tokens in the input prompt.
    public let promptTokens: Int?

    /// Number of tokens in the generated completion.
    public let completionTokens: Int?

    /// Total number of tokens used (prompt + completion).
    public let totalTokens: Int?

    /// Number of tokens retrieved from cache (if prompt caching is used).
    public let cachedTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case cachedTokens = "cached_tokens"
    }

    /// Creates a new token usage instance.
    ///
    /// - Parameters:
    ///   - promptTokens: Number of tokens in the input prompt.
    ///   - completionTokens: Number of tokens in the generated completion.
    ///   - totalTokens: Total number of tokens used.
    ///   - cachedTokens: Number of tokens retrieved from cache.
    public init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        cachedTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
    }

    /// Adds two token usage instances together.
    ///
    /// - Parameters:
    ///   - lhs: The first token usage.
    ///   - rhs: The second token usage.
    /// - Returns: A new token usage with summed values.
    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            promptTokens: (lhs.promptTokens ?? 0) + (rhs.promptTokens ?? 0),
            completionTokens: (lhs.completionTokens ?? 0) + (rhs.completionTokens ?? 0),
            totalTokens: (lhs.totalTokens ?? 0) + (rhs.totalTokens ?? 0),
            cachedTokens: (lhs.cachedTokens ?? 0) + (rhs.cachedTokens ?? 0)
        )
    }

    /// Adds another token usage to this instance.
    ///
    /// - Parameters:
    ///   - lhs: The token usage to modify.
    ///   - rhs: The token usage to add.
    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }
}

/// Metadata associated with a language model response.
///
/// This type provides extensible metadata that models can attach to their responses,
/// such as token usage information, model version, or other provider-specific data.
public struct ResponseMetadata: Sendable, Hashable {
    /// Token usage information for this response.
    public var tokenUsage: TokenUsage?

    /// Creates new response metadata.
    ///
    /// - Parameter tokenUsage: Token usage information.
    public init(tokenUsage: TokenUsage? = nil) {
        self.tokenUsage = tokenUsage
    }
}
