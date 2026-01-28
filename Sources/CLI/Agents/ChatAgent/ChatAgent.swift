import Foundation
import SwiftAgentCore

enum ChatAgent {
    static let agent = Agent(
        id: "chat",
        name: "Chat Agent",
        description: "An agent that performs the first task.",
        modelName: "doubao",
        instructions: instructions,
        mcpServerNames: ["PlaywrightMCP"]
    )
}
