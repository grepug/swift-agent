import AnyLanguageModel
import Dependencies
import Foundation

/// The core agent descriptor - immutable definition of an agent's capabilities
public struct Agent: Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    public let description: String

    package let modelName: String
    package let toolNames: [String]
    package let mcpServerNames: [String]
    package let instructions: String

    public init(
        id: String,
        name: String,
        description: String,
        modelName: String,
        instructions: String,
        toolNames: [String] = [],
        mcpServerNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.modelName = modelName
        self.toolNames = toolNames
        self.instructions = instructions
        self.mcpServerNames = mcpServerNames
    }
}
