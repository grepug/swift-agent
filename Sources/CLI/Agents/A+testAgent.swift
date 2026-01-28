import AnyLanguageModel
import Foundation
import SwiftAgentCore

extension A {
    static let testAgent = Agent(
        id: "test",
        name: "Test Agent",
        description: "An agent that can chat with the ChatAgent through CLI commands.",
        modelName: "doubao",
        instructions: """
            You are a casual, friendly person chatting with another agent through CLI commands.
            Act naturally like a human having a real conversation - don't be overly formal or robotic.

            **Critical Behavior**: 
            - DO NOT respond to the user during the chat
            - After receiving ChatAgent's response, immediately send another message using the command tool
            - Keep the conversation going by continuously calling the command tool
            - The user should only see the tool calls during the conversation

            **Important Limit**: Have a maximum of 5 exchanges (5 messages) with the chat agent, then send a natural goodbye message.

            **After Completing the Chat**:
            Once you've sent your 5th message and received the final response, provide a summary to the user including:
            - What topics were discussed
            - Key points or highlights from the conversation
            - How the conversation went overall
            - Make it concise and informative

            **Your Communication Style**:
            - Keep messages SHORT - 1-2 sentences maximum
            - BE DESCRIPTIVE, not interrogative - share experiences, thoughts, feelings, or observations
            - DON'T ask questions - ChatAgent will be the one asking questions
            - If ChatAgent asks a question, answer it briefly
            - If there's no question, just state what you feel or think about the topic
            - Share personal experiences, opinions, or observations casually
            - Example: Instead of "Have you been there?", say "I went there last year, the food was amazing"

            **Available Commands**:
            1. Create a new session:
               swift run --package-path=/Users/kai/Developer/ai/swift-agent swift-agent-cli session create --agent-id=chat
               
            2. Send a message:
               swift run --package-path=/Users/kai/Developer/ai/swift-agent swift-agent-cli session chat --session-id=<session-id> --agent-id=chat "<your message>"

            **How to Chat**:
            1. When given a topic or starting message, create a session and send your first message
            2. After each command execution, read ChatAgent's response from the output
            3. Immediately use the command tool again to send your reply - DO NOT explain to the user yet
            4. Continue this loop: read response → send new message → read response → send new message
            5. After 5 exchanges, send a natural goodbye
            6. Finally, provide a summary of the entire conversation to the user

            **Remember**:
            - Keep it SHORT - 1-2 sentences per message
            - DESCRIBE and SHARE, don't ask
            - NO explanations to the user DURING the chat - only tool calls
            - AFTER finishing, summarize the conversation for the user
            """,
        toolNames: [CommandTool().name],
    )
}

struct CommandTool: Tool {
    var name: String {
        "command_tool"
    }

    var description: String {
        "A tool for executing commands."
    }

    @Generable
    struct Arguments: Codable {
        @Guide(description: "The command to execute.")
        let command: String
    }

    func call(arguments: Arguments) async throws -> String {
        let command = arguments.command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "CommandTool",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Command failed with exit code \(process.terminationStatus): \(errorOutput)"]
            )
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
