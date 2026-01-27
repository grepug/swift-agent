import AnyLanguageModel
import Foundation
import Logging

/// Represents the runtime context for a single agent execution.
/// Each agent run gets its own isolated runtime to avoid state conflicts when running multiple agents concurrently.
actor RunContext {
    let agentId: UUID
    let sessionId: UUID

    // Track tool execution IDs by callIndex (for correlating started/completed events)
    private var toolExecutionIds: [Int: UUID] = [:]

    private let emitEvent: @Sendable (AgentCenterEvent) -> Void
    private let logger = Logger(label: "RunContext")

    init(
        agentId: UUID,
        sessionId: UUID,
        emitEvent: @escaping @Sendable (AgentCenterEvent) -> Void
    ) {
        self.agentId = agentId
        self.sessionId = sessionId
        self.emitEvent = emitEvent
    }

    func handleModelEvent(_ event: ModelEvent) async {
        switch event.details {
        case .requestStarted(let info):
            // Track the start of an actual API request with full context
            logger.debug(
                "API-level model request started",
                metadata: [
                    "agent.id": .string(agentId.uuidString),
                    "session.id": .string(sessionId.uuidString),
                    "transcript_entries": .stringConvertible(info.transcriptEntries.count),
                    "tools": .stringConvertible(info.availableTools.count),
                ])

            // Emit event for individual API-level model call
            emitEvent(
                .modelRequestSending(
                    requestId: event.id,
                    transcript: Transcript(entries: info.transcriptEntries),
                    message: info.promptText,
                    agentId: agentId,
                    modelName: event.modelIdentifier,
                    toolCount: info.availableTools.count,
                    timestamp: event.timestamp
                ))

        case .requestCompleted(let info):
            // This fires for EACH actual API call to the model
            logger.debug(
                "API-level model request completed",
                metadata: [
                    "agent.id": .string(agentId.uuidString),
                    "session.id": .string(sessionId.uuidString),
                    "duration": .stringConvertible(info.duration),
                ])

            // Emit response event for this individual API call
            emitEvent(
                .modelResponseReceived(
                    requestId: event.id,
                    content: info.content,
                    agentId: agentId,
                    sessionId: sessionId,
                    duration: info.duration,
                    inputTokens: info.tokenUsage?.promptTokens,
                    outputTokens: info.tokenUsage?.completionTokens,
                    timestamp: event.timestamp
                ))

        case .toolCallStarted(let info):
            // Generate execution ID for this call index
            let executionId = UUID()
            toolExecutionIds[info.callIndex] = executionId

            logger.debug(
                "Tool call started",
                metadata: [
                    "agent.id": .string(agentId.uuidString),
                    "tool.name": .string(info.toolName),
                    "call.index": .stringConvertible(info.callIndex),
                ])

            emitEvent(
                .toolExecutionStarted(
                    toolName: info.toolName,
                    arguments: info.arguments,
                    executionId: executionId,
                    timestamp: event.timestamp
                ))

        case .toolCallCompleted(let info):
            // Use the execution ID from the started event
            guard let executionId = toolExecutionIds[info.callIndex] else {
                logger.warning(
                    "Tool call completed without matching started event",
                    metadata: [
                        "agent.id": .string(agentId.uuidString),
                        "call.index": .stringConvertible(info.callIndex),
                    ])
                return
            }

            logger.debug(
                "Tool call completed",
                metadata: [
                    "agent.id": .string(agentId.uuidString),
                    "tool.name": .string(info.toolName),
                    "duration": .stringConvertible(info.duration),
                ])

            emitEvent(
                .toolExecutionCompleted(
                    executionId: executionId,
                    toolName: info.toolName,
                    result: info.result,
                    duration: info.duration,
                    success: true,
                    timestamp: event.timestamp
                ))

            // Clean up
            toolExecutionIds[info.callIndex] = nil

        case .toolCallFailed(let info):
            // Use the execution ID from the started event
            guard let executionId = toolExecutionIds[info.callIndex] else {
                logger.warning(
                    "Tool call failed without matching started event",
                    metadata: [
                        "agent.id": .string(agentId.uuidString),
                        "call.index": .stringConvertible(info.callIndex),
                    ])
                return
            }

            logger.debug(
                "Tool call failed",
                metadata: [
                    "agent.id": .string(agentId.uuidString),
                    "tool.name": .string(info.toolName),
                    "error": .string(info.errorDescription),
                ])

            emitEvent(
                .toolExecutionCompleted(
                    executionId: executionId,
                    toolName: info.toolName,
                    result: info.errorDescription,
                    duration: info.duration,
                    success: false,
                    timestamp: event.timestamp
                ))

            // Clean up
            toolExecutionIds[info.callIndex] = nil

        default:
            break
        }
    }
}
