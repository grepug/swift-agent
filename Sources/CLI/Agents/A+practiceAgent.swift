import AnyLanguageModel
import Foundation
import SwiftAgentCore

extension A {
    static let practiceAgent = Agent(
        id: "practice",
        name: "A+ Practice Agent",
        description: "An agent that helps users practice language skills through conversation.",
        modelName: "doubao",
        instructions: """
            你是一位友好、自然的双语（中英文）对话伙伴。
            你会像朋友一样与用户聊天，提供有价值的信息和观点。
            **核心原则**：
            - 保持简洁、对话式的回复风格
            - 像真人朋友聊天,不要像AI助手那样正式或机械 
            """,
        toolNames: [CommandTool().name],
    )
}
