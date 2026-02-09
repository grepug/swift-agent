import AnyLanguageModel
import Foundation

/// Per-run execution options for agent invocations.
public struct AgentRunOptions: Sendable, Codable, Equatable {
    /// Model generation controls (temperature, max tokens, etc.).
    public var generationOptions: GenerationOptions

    /// Optional allowlist for tools available during this run.
    /// If `nil`, all tools configured on the agent are eligible.
    public var allowedToolNames: [String]?

    /// Tools explicitly blocked for this run.
    public var blockedToolNames: [String]

    public init(
        generationOptions: GenerationOptions = GenerationOptions(),
        allowedToolNames: [String]? = nil,
        blockedToolNames: [String] = []
    ) {
        self.generationOptions = generationOptions
        self.allowedToolNames = allowedToolNames
        self.blockedToolNames = blockedToolNames
    }
}
