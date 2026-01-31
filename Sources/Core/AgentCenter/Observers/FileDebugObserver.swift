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

        case .agentExecutionCompleted(let run, _):
            handleAgentExecutionCompleted(run: run)

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

            // Look for existing session directory or create new one
            let uuidPrefix = uuidPrefix(sessionId)
            let sessionDir = findOrCreateSessionDirectory(
                in: agentDir,
                sessionId: sessionId,
                uuidPrefix: uuidPrefix
            )

            // Determine next run number
            let runNumber = getNextRunNumber(in: sessionDir)
            let runDirName = String(format: "run-%03d", runNumber)
            let runDir = sessionDir.appendingPathComponent(runDirName)
            try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

            store.sessionDirectories[sessionId] = sessionDir
            store.runCounters[sessionId] = runNumber
            store.currentRunSession = sessionId
            store.fileCounters[sessionId] = 1

            // Track start time
            store.sessionStartTime[sessionId] = Date()
        }
    }

    private func findOrCreateSessionDirectory(
        in agentDir: URL,
        sessionId: UUID,
        uuidPrefix: String
    ) -> URL {
        // Look for existing directory with this session ID prefix
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: agentDir,
            includingPropertiesForKeys: nil
        ) {
            for dir in contents where dir.hasDirectoryPath {
                // Check if directory name ends with the session UUID prefix
                if dir.lastPathComponent.hasSuffix("-\(uuidPrefix)") {
                    return dir
                }
            }
        }

        // No existing directory found, create new one with timestamp
        let timestamp = formatTimestamp(Date())
        let sessionDirName = "\(timestamp)-\(uuidPrefix)"
        let sessionDir = agentDir.appendingPathComponent(sessionDirName)
        try? FileManager.default.createDirectory(
            at: sessionDir,
            withIntermediateDirectories: true
        )
        return sessionDir
    }

    private func getNextRunNumber(in sessionDir: URL) -> Int {
        // Find existing run directories and get the highest number
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: sessionDir,
                includingPropertiesForKeys: nil
            )
        else {
            return 1
        }

        let runNumbers =
            contents
            .filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("run-") }
            .compactMap { dir -> Int? in
                let name = dir.lastPathComponent
                let numberStr = name.replacingOccurrences(of: "run-", with: "")
                return Int(numberStr)
            }

        return (runNumbers.max() ?? 0) + 1
    }

    private func handleAgentExecutionCompleted(run: Run) {
        store.withValue { store in
            let sessionId = run.sessionId

            guard let sessionDir = store.sessionDirectories[sessionId],
                let agentId = store.sessionAgents[sessionId],
                let runNumber = store.runCounters[sessionId]
            else { return }

            let runDirName = String(format: "run-%03d", runNumber)
            let runDir = sessionDir.appendingPathComponent(runDirName)

            // Collect all events (API calls and tool calls) with their timestamps
            var events: [(timestamp: Date, write: (URL, Int) -> Void)] = []

            // Add model calls
            let modelCalls = store.sessionModelCalls[sessionId] ?? [:]
            for (_, callData) in modelCalls {
                events.append(
                    (
                        timestamp: callData.startTime,
                        write: { dir, number in
                            self.writeAPICallFile(callData, to: dir, number: number)
                        }
                    ))
            }

            // Add tool calls
            let toolCalls = store.sessionToolCalls[sessionId] ?? [:]
            for (_, callData) in toolCalls {
                events.append(
                    (
                        timestamp: callData.startTime,
                        write: { dir, number in
                            self.writeToolCallFile(callData, to: dir, number: number)
                        }
                    ))
            }

            // Sort by timestamp and write files in chronological order
            let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
            for (index, event) in sortedEvents.enumerated() {
                let fileNumber = index + 1
                event.write(runDir, fileNumber)
            }

            // Write summary file for this run
            let inputTokens = modelCalls.values.compactMap(\.inputTokens).reduce(0, +)
            let outputTokens = modelCalls.values.compactMap(\.outputTokens).reduce(0, +)

            writeSummary(
                to: runDir,
                sessionId: sessionId,
                agentId: agentId,
                store: &store,
                endTime: Date(),
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )

            store.currentRunSession = nil
        }
    }

    private func handleAgentExecutionFailed(sessionId: UUID, error: Error) {
        store.withValue { store in
            guard let sessionDir = store.sessionDirectories[sessionId],
                let agentId = store.sessionAgents[sessionId],
                let runNumber = store.runCounters[sessionId]
            else { return }

            store.sessionFinalResponse[sessionId] = "Error: \(error)"

            let runDirName = String(format: "run-%03d", runNumber)
            let runDir = sessionDir.appendingPathComponent(runDirName)

            writeSummary(
                to: runDir,
                sessionId: sessionId,
                agentId: agentId,
                store: &store,
                endTime: Date(),
                inputTokens: nil,
                outputTokens: nil
            )

            store.currentRunSession = nil
        }
    }

    private func writeSummary(
        to directory: URL,
        sessionId: UUID,
        agentId: String,
        store: inout Store,
        endTime: Date,
        inputTokens: Int?,
        outputTokens: Int?
    ) {
        writeSummaryFile(
            to: directory,
            sessionId: sessionId,
            agentId: agentId,
            userInput: store.sessionUserInput[sessionId],
            finalResponse: store.sessionFinalResponse[sessionId],
            modelName: store.sessionModelName[sessionId],
            startTime: store.sessionStartTime[sessionId],
            endTime: endTime,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
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
            updateModelCall(
                sessionId: sessionId,
                requestId: requestId,
                in: &store
            ) { callData in
                callData.responseContent = content
                callData.responseTime = Date()
                callData.duration = duration
                callData.inputTokens = inTokens
                callData.outputTokens = outTokens
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
            guard let sessionId = store.currentRunSession else { return }

            updateToolCall(
                sessionId: sessionId,
                executionId: executionId,
                in: &store
            ) { callData in
                callData.result = result
                callData.endTime = Date()
                callData.duration = duration
                callData.success = success
            }

            // Don't write file here - will be written in chronological order when run completes
        }
    }

    // MARK: - Helper Methods

    private func updateModelCall(
        sessionId: UUID,
        requestId: UUID,
        in store: inout Store,
        update: (inout ModelCallData) -> Void
    ) {
        var callsForSession = store.sessionModelCalls[sessionId] ?? [:]
        if var callData = callsForSession[requestId] {
            update(&callData)
            callsForSession[requestId] = callData
            store.sessionModelCalls[sessionId] = callsForSession
        }
    }

    private func updateToolCall(
        sessionId: UUID,
        executionId: UUID,
        in store: inout Store,
        update: (inout ToolCallData) -> Void
    ) {
        var callsForSession = store.sessionToolCalls[sessionId] ?? [:]
        if var callData = callsForSession[executionId] {
            update(&callData)
            callsForSession[executionId] = callData
            store.sessionToolCalls[sessionId] = callsForSession
        }
    }
}
