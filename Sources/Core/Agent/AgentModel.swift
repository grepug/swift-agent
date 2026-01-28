import Foundation

/// Represents a language model configuration that can be converted to an OpenAILanguageModel
///
/// - Warning: This struct stores API keys as plain String values. For production use,
///   consider using more secure approaches such as:
///   - Keychain storage for API keys
///   - Environment variables
///   - Secure configuration management systems
///   - Never commit API keys to version control
public struct AgentModel: Sendable, Codable, Hashable {
    /// The name/identifier for this model (e.g., "gpt-4", "claude-3-sonnet")
    public let name: String

    /// The base URL for the API endpoint
    public let baseURL: URL

    /// The model ID to use with the API
    public let id: String

    /// The API key for authentication
    public let apiKey: String

    public init(
        name: String,
        baseURL: URL,
        id: String,
        apiKey: String
    ) {
        self.name = name
        self.baseURL = baseURL
        self.id = id
        self.apiKey = apiKey
    }
}
