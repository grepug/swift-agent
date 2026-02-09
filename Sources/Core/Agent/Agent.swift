import AnyLanguageModel
import Dependencies
import Foundation

/// The core agent descriptor - immutable definition of an agent's capabilities
public struct Agent: Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    public let description: String

    public let modelName: String
    public let toolNames: [String]
    public let mcpServerNames: [String]
    public let preHookNames: [String]
    public let postHookNames: [String]
    public let instructions: String

    public init(
        id: String,
        name: String,
        description: String,
        modelName: String,
        instructions: String,
        toolNames: [String] = [],
        mcpServerNames: [String] = [],
        preHookNames: [String] = [],
        postHookNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.modelName = modelName
        self.toolNames = toolNames
        self.instructions = instructions
        self.mcpServerNames = mcpServerNames
        self.preHookNames = preHookNames
        self.postHookNames = postHookNames
    }

    public init(
        name: String,
        description: String,
        modelName: String,
        instructions: String,
        toolNames: [String] = [],
        mcpServerNames: [String] = [],
        preHookNames: [String] = [],
        postHookNames: [String] = []
    ) {
        self.init(
            id: UUID().uuidString,
            name: name,
            description: description,
            modelName: modelName,
            instructions: instructions,
            toolNames: toolNames,
            mcpServerNames: mcpServerNames,
            preHookNames: preHookNames,
            postHookNames: postHookNames
        )
    }
}
