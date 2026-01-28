import AnyLanguageModel
import Foundation

extension FileDebugObserver {
    struct Store {
        // Track session directories
        var sessionDirectories: [UUID: URL] = [:]  // sessionId -> directory
        var runCounters: [UUID: Int] = [:]  // sessionId -> run number (unused for now, always 1)
        var fileCounters: [UUID: Int] = [:]  // sessionId -> next file number

        // Track agent IDs per session for directory structure
        var sessionAgents: [UUID: String] = [:]  // sessionId -> agentId

        // Track calls per session
        var sessionModelCalls: [UUID: [UUID: ModelCallData]] = [:]  // sessionId -> requestId -> data
        var sessionToolCalls: [UUID: [UUID: ToolCallData]] = [:]  // sessionId -> executionId -> data
        var currentRunSession: UUID?  // The session that has an active run in progress

        // Track run summary data
        var sessionUserInput: [UUID: String] = [:]  // sessionId -> initial user message
        var sessionFinalResponse: [UUID: String] = [:]  // sessionId -> final model response
        var sessionStartTime: [UUID: Date] = [:]  // sessionId -> run start time
        var sessionModelName: [UUID: String] = [:]  // sessionId -> model name/ID
    }

    // Track in-progress model calls
    struct ModelCallData {
        let requestId: UUID
        let transcript: Transcript
        let message: String
        let modelName: String
        let toolCount: Int
        let startTime: Date
        var responseContent: String?
        var responseTime: Date?
        var duration: TimeInterval?
        var inputTokens: Int?
        var outputTokens: Int?
    }

    // Track in-progress tool calls
    struct ToolCallData {
        let executionId: UUID
        let toolName: String
        let arguments: String
        let startTime: Date
        var result: String?
        var endTime: Date?
        var duration: TimeInterval?
        var success: Bool?
    }
}
