import AnyLanguageModel
import Dependencies
import Foundation

/// File-based debug observer that writes detailed execution logs to disk
public final class FileDebugObserver: AgentCenterObserver {
    private let debugDir: URL
    private let store: LockIsolated<Store>

    public init(debugDir: URL = URL(fileURLWithPath: "debug")) {
        self.debugDir = debugDir
        self.store = LockIsolated(Store())

        // Create debug directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: debugDir,
            withIntermediateDirectories: true
        )
    }

    public func observe(_ event: AgentCenterEvent) {
        switch event {
        case .agentExecutionStarted(let agent, let session, _):
            handleAgentExecutionStarted(agentId: agent.id, sessionId: session.sessionId)

        case .agentExecutionCompleted:
            // We can get the sessionId from the run
            // For now, we'll handle summary in the failed case or when we get the response
            break

        case .agentExecutionFailed(let session, let error, _):
            handleAgentExecutionFailed(sessionId: session.sessionId, error: error)

        case .modelRequestSending(let requestId, let transcript, let message, let agentId, let modelName, let toolCount, _):
            handleModelRequestSending(
                agentId: agentId,
                transcript: transcript,
                message: message,
                modelName: modelName,
                toolCount: toolCount,
                requestId: requestId
            )

        case .modelResponseReceived(let requestId, let content, let agentId, let sessionId, let duration, let inTokens, let outTokens, _):
            handleModelResponseReceived(
                sessionId: sessionId,
                content: content,
                requestId: requestId,
                agentId: agentId,
                duration: duration,
                inTokens: inTokens,
                outTokens: outTokens
            )

        case .transcriptBuilt(let transcript, let agentId, _, _):
            handleTranscriptBuilt(transcript: transcript, agentId: agentId)

        case .toolExecutionStarted(let toolName, let args, let executionId, _):
            handleToolExecutionStarted(tool: toolName, args: args, executionId: executionId)

        case .toolExecutionCompleted(let executionId, let toolName, let result, let duration, let success, _):
            handleToolExecutionCompleted(
                executionId: executionId,
                tool: toolName,
                result: result,
                duration: duration,
                success: success
            )

        default:
            break
        }
    }

    // MARK: - Event Handlers

    private func handleAgentExecutionStarted(agentId: String, sessionId: UUID) {
        store.withValue { store in
            // Store the agent ID for this session
            store.sessionAgents[sessionId] = agentId

            // Create agents/[sanitized-agent-id] directory
            let sanitizedAgentId = sanitizeAgentId(agentId)
            let agentsDir = debugDir.appendingPathComponent("agents")
            let agentDir = agentsDir.appendingPathComponent(sanitizedAgentId)
            try? FileManager.default.createDirectory(
                at: agentDir,
                withIntermediateDirectories: true
            )

            // Create session directory: [yyyyMMddHHmmss-6char]
            let timestamp = formatTimestamp(Date())
            let uuidPrefix = uuidPrefix(sessionId)
            let sessionDirName = "\(timestamp)-\(uuidPrefix)"
            let sessionDir = agentDir.appendingPathComponent(sessionDirName)

            // Check for collision (should be extremely rare)
            if FileManager.default.fileExists(atPath: sessionDir.path) {
                fatalError("Session directory already exists: \(sessionDir.path)")
            }

            try? FileManager.default.createDirectory(
                at: sessionDir,
                withIntermediateDirectories: true
            )

            // Create initial run directory
            let runDirName = "run-001"
            let runDir = sessionDir.appendingPathComponent(runDirName)
            try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

            store.sessionDirectories[sessionId] = sessionDir
            // We'll track the run dir when we get the first model request
            store.runCounters[sessionId] = 1
            store.currentRunSession = sessionId
            store.fileCounters[sessionId] = 1

            // Track start time
            store.sessionStartTime[sessionId] = Date()
        }
    }

    private func handleAgentExecutionFailed(sessionId: UUID, error: Error) {
        store.withValue { store in
            guard let sessionDir = store.sessionDirectories[sessionId],
                let agentId = store.sessionAgents[sessionId]
            else { return }

            let errorMessage = "Error: \(error)"
            store.sessionFinalResponse[sessionId] = errorMessage

            writeSummaryFile(
                to: sessionDir,
                sessionId: sessionId,
                agentId: agentId,
                userInput: store.sessionUserInput[sessionId],
                finalResponse: errorMessage,
                modelName: store.sessionModelName[sessionId],
                startTime: store.sessionStartTime[sessionId],
                endTime: Date(),
                inputTokens: nil,
                outputTokens: nil
            )

            store.currentRunSession = nil
        }
    }

    private func handleModelRequestSending(
        agentId: String,
        transcript: Transcript,
        message: String,
        modelName: String,
        toolCount: Int,
        requestId: UUID
    ) {
        store.withValue { store in
            // Find the session for this agent
            guard let sessionId = store.sessionAgents.first(where: { $0.value == agentId })?.key else { return }

            // Track this model call
            var callsForSession = store.sessionModelCalls[sessionId] ?? [:]
            callsForSession[requestId] = ModelCallData(
                requestId: requestId,
                transcript: transcript,
                message: message,
                modelName: modelName,
                toolCount: toolCount,
                startTime: Date()
            )
            store.sessionModelCalls[sessionId] = callsForSession

            // Store model name for summary and user input (first prompt)
            store.sessionModelName[sessionId] = modelName
            if store.sessionUserInput[sessionId] == nil {
                store.sessionUserInput[sessionId] = message
            }
        }
    }

    private func handleModelResponseReceived(
        sessionId: UUID,
        content: String,
        requestId: UUID,
        agentId: String,
        duration: TimeInterval,
        inTokens: Int?,
        outTokens: Int?
    ) {
        store.withValue { store in
            // Update the model call data
            var callsForSession = store.sessionModelCalls[sessionId] ?? [:]
            if var callData = callsForSession[requestId] {
                callData.responseContent = content
                callData.responseTime = Date()
                callData.duration = duration
                callData.inputTokens = inTokens
                callData.outputTokens = outTokens
                callsForSession[requestId] = callData
                store.sessionModelCalls[sessionId] = callsForSession
            }

            // Store final response
            store.sessionFinalResponse[sessionId] = content
        }
    }

    private func handleTranscriptBuilt(transcript: Transcript, agentId: String) {
        // Currently not writing transcript separately
    }

    private func handleToolExecutionStarted(tool: String, args: String, executionId: UUID) {
        store.withValue { store in
            guard let sessionId = store.currentRunSession else { return }

            var callsForSession = store.sessionToolCalls[sessionId] ?? [:]
            callsForSession[executionId] = ToolCallData(
                executionId: executionId,
                toolName: tool,
                arguments: args,
                startTime: Date()
            )
            store.sessionToolCalls[sessionId] = callsForSession
        }
    }

    private func handleToolExecutionCompleted(
        executionId: UUID,
        tool: String,
        result: String,
        duration: TimeInterval,
        success: Bool
    ) {
        store.withValue { store in
            guard let sessionId = store.currentRunSession,
                let sessionDir = store.sessionDirectories[sessionId]
            else { return }

            // Get the run directory (run-001)
            let runDir = sessionDir.appendingPathComponent("run-001")

            var callsForSession = store.sessionToolCalls[sessionId] ?? [:]
            if var callData = callsForSession[executionId] {
                callData.result = result
                callData.endTime = Date()
                callData.duration = duration
                callData.success = success
                callsForSession[executionId] = callData
                store.sessionToolCalls[sessionId] = callsForSession

                // Write tool call file
                let fileNumber = store.fileCounters[sessionId] ?? 1
                store.fileCounters[sessionId] = fileNumber + 1
                writeToolCallFile(callData, to: runDir, number: fileNumber)
            }
        }
    }
}
