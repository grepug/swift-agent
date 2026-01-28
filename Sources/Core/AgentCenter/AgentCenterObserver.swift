import AnyLanguageModel
import Dependencies
import Foundation

/// Protocol for observing agent center events
public protocol AgentCenterObserver: Sendable {
    /// Called when an event occurs in the agent center
    func observe(_ event: AgentCenterEvent)
}

// MARK: - Default Implementations

/// Silent observer that does nothing (default)
public struct SilentObserver: AgentCenterObserver {
    public init() {}

    public func observe(_ event: AgentCenterEvent) {
        // No-op
    }
}

/// Console observer that prints events to stdout
public struct ConsoleObserver: AgentCenterObserver {
    private let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    public func observe(_ event: AgentCenterEvent) {
        let timestamp = ISO8601DateFormatter().string(from: event.timestamp)
        print("[\(timestamp)] \(event.description)")

        if verbose {
            printVerboseDetails(for: event)
        }
    }

    private func printVerboseDetails(for event: AgentCenterEvent) {
        switch event {
        case .modelRequestSending(_, let transcript, let message, _, _, _, _):
            print("  Message: \(message)")
            print("  Transcript entries: \(transcript.count)")
        case .modelResponseReceived(_, let content, _, _, let duration, let inTokens, let outTokens, _):
            print("  Response: \(content)")
            print("  Duration: \(String(format: "%.3f", duration))s")
            if let inTokens = inTokens {
                print("  Input tokens: \(inTokens)")
            }
            if let outTokens = outTokens {
                print("  Output tokens: \(outTokens)")
            }
        case .transcriptBuilt(let transcript, _, _, _):
            print("  Transcript entries: \(transcript.count)")
        case .toolExecutionStarted(let tool, let args, _, _):
            print("  Tool: \(tool)")
            print("  Arguments: \(args.prefix(100))\(args.count > 100 ? "..." : "")")
        case .toolExecutionCompleted(_, let tool, let result, let duration, let success, _):
            print("  Tool: \(tool)")
            print("  Duration: \(String(format: "%.3f", duration))s")
            print("  Success: \(success)")
            print("  Result: \(result.prefix(100))\(result.count > 100 ? "..." : "")")
        default:
            break
        }
    }
}

/// File-based debug observer that writes events to disk
/// Creates one file per model call/tool execution in run-specific folders
public final class FileDebugObserver: AgentCenterObserver {
    private let directory: URL
    private var fileManager: FileManager { FileManager.default }

    // usage:
    // to mutate: store.withValue { $0.property = newValue }
    // to read:   store.value.[PROPERTY]
    private let store = LockIsolated<Store>(.init())

    private struct Store {
        // Track run directories
        var sessionDirectories: [UUID: URL] = [:]  // sessionId -> directory
        var runCounters: [UUID: Int] = [:]  // sessionId -> run number
        var runDirectories: [UUID: URL] = [:]  // runId -> run folder
        var fileCounters: [UUID: Int] = [:]  // runId -> next file number

        // Track agent IDs per session for directory structure
        var sessionAgents: [UUID: String] = [:]  // sessionId -> agentId

        // Track calls per session
        var sessionModelCalls: [UUID: [UUID: ModelCallData]] = [:]  // sessionId -> requestId -> data
        var sessionToolCalls: [UUID: [UUID: ToolCallData]] = [:]  // sessionId -> executionId -> data
        var sessionAPIModelCalls: [UUID: [UUID: APIModelCallData]] = [:]  // sessionId -> eventId -> data
        var currentRunSession: UUID?  // The session that has an active run in progress

        // Track run summary data
        var sessionUserInput: [UUID: String] = [:]  // sessionId -> initial user message
        var sessionFinalResponse: [UUID: String] = [:]  // sessionId -> final model response
        var sessionStartTime: [UUID: Date] = [:]  // sessionId -> run start time
        var sessionModelName: [UUID: String] = [:]  // sessionId -> model name/ID
    }

    // Track in-progress model calls
    private struct ModelCallData {
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
    private struct ToolCallData {
        let executionId: UUID
        let toolName: String
        let arguments: String
        let startTime: Date
        var result: String?
        var endTime: Date?
        var duration: TimeInterval?
        var success: Bool?
    }

    // Track individual API-level model calls (from AnyLanguageModel events)
    private struct APIModelCallData {
        let eventId: UUID
        let transcriptEntries: [Transcript.Entry]
        let availableTools: [String]
        let startTime: Date
        var responseContent: String?
        var responseTime: Date?
        var duration: TimeInterval?
        var inputTokens: Int?
        var outputTokens: Int?
    }

    public init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Sanitize agent ID for use in directory names: lowercase and replace whitespace with hyphens
    private func sanitizeAgentId(_ agentId: String) -> String {
        return agentId.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Format timestamp as YYYYMMDDHHMMSS in local timezone
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Get first 6 characters of UUID string (lowercase)
    private func uuidPrefix(_ uuid: UUID) -> String {
        return String(uuid.uuidString.lowercased().prefix(6))
    }

    public func observe(_ event: AgentCenterEvent) {
        // Always log to events.log
        writeEventLog(event)

        switch event {
        case .agentExecutionStarted(let agent, let session, let timestamp):
            // Track session and prepare for new run
            store.withValue { store in
                store.currentRunSession = session.sessionId
                store.sessionStartTime[session.sessionId] = timestamp
                store.sessionAgents[session.sessionId] = agent.id

                if store.sessionDirectories[session.sessionId] == nil {
                    // Create directory structure: agents/[agentId]/[timestamp-uuid]/
                    let sanitizedAgentId = sanitizeAgentId(agent.id)
                    let agentDir =
                        directory
                        .appendingPathComponent("agents")
                        .appendingPathComponent(sanitizedAgentId)

                    let timestampStr = formatTimestamp(timestamp)
                    let uuidPrefixStr = uuidPrefix(session.sessionId)
                    let sessionDirName = "\(timestampStr)-\(uuidPrefixStr)"
                    let sessionDir = agentDir.appendingPathComponent(sessionDirName)

                    // Check for collision (should be extremely rare)
                    if fileManager.fileExists(atPath: sessionDir.path) {
                        fatalError("Session directory collision: \(sessionDir.path)")
                    }

                    try? fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
                    store.sessionDirectories[session.sessionId] = sessionDir
                    store.runCounters[session.sessionId] = 0
                }
                store.runCounters[session.sessionId] = (store.runCounters[session.sessionId] ?? 0) + 1

                // Initialize empty call tracking for this run
                store.sessionModelCalls[session.sessionId] = [:]
                store.sessionToolCalls[session.sessionId] = [:]
                store.sessionAPIModelCalls[session.sessionId] = [:]
            }

        case .modelRequestSending(let requestId, let transcript, _, _, let modelName, let toolCount, let timestamp):
            // This event comes from handleModelEvent (requestStarted) - represents individual API calls
            // Store as API-level call to write separate files for each actual model API request
            store.withValue { store in
                guard let sessionId = store.currentRunSession else { return }
                if store.sessionAPIModelCalls[sessionId] == nil {
                    store.sessionAPIModelCalls[sessionId] = [:]
                }

                // Convert Transcript to array of entries for storage
                let entries = (0..<transcript.count).compactMap { transcript[$0] }

                // Capture model name (first API call)
                if store.sessionModelName[sessionId] == nil {
                    store.sessionModelName[sessionId] = modelName
                }

                // Capture user input from first API call (last entry should be the user prompt)
                if store.sessionUserInput[sessionId] == nil {
                    if let lastEntry = entries.last, case .prompt(let prompt) = lastEntry {
                        let userText = prompt.segments.compactMap { segment in
                            if case .text(let text) = segment { return text.content }
                            return nil
                        }.joined(separator: "\n")
                        store.sessionUserInput[sessionId] = userText
                    }
                }

                store.sessionAPIModelCalls[sessionId]?[requestId] = APIModelCallData(
                    eventId: requestId,
                    transcriptEntries: entries,
                    availableTools: (0..<toolCount).map { "tool\($0)" },  // We don't have tool names here
                    startTime: timestamp,
                    responseContent: nil,
                    responseTime: nil,
                    duration: nil,
                    inputTokens: nil,
                    outputTokens: nil
                )
            }

        case .modelResponseReceived(let requestId, let content, _, _, let duration, let inputTokens, let outputTokens, let timestamp):
            // Update API-level model call with response data
            store.withValue { store in
                guard let sessionId = store.currentRunSession else { return }
                if var callData = store.sessionAPIModelCalls[sessionId]?[requestId] {
                    callData.responseContent = content
                    callData.responseTime = timestamp
                    callData.duration = duration
                    callData.inputTokens = inputTokens
                    callData.outputTokens = outputTokens
                    store.sessionAPIModelCalls[sessionId]?[requestId] = callData

                    // Update final response (last non-empty response wins)
                    if !content.isEmpty {
                        store.sessionFinalResponse[sessionId] = content
                    }
                }
            }

        case .toolExecutionStarted(let toolName, let arguments, let executionId, let timestamp):
            // Store tool execution state for current run session
            store.withValue { store in
                guard let sessionId = store.currentRunSession else { return }
                if store.sessionToolCalls[sessionId] == nil {
                    store.sessionToolCalls[sessionId] = [:]
                }
                store.sessionToolCalls[sessionId]?[executionId] = ToolCallData(
                    executionId: executionId,
                    toolName: toolName,
                    arguments: arguments,
                    startTime: timestamp,
                    result: nil,
                    endTime: nil,
                    duration: nil,
                    success: nil
                )
            }

        case .toolExecutionCompleted(let executionId, _, let result, let duration, let success, let timestamp):
            // Update tool execution with completion data
            store.withValue { store in
                guard let sessionId = store.currentRunSession else { return }
                if var toolData = store.sessionToolCalls[sessionId]?[executionId] {
                    toolData.result = result
                    toolData.endTime = timestamp
                    toolData.duration = duration
                    toolData.success = success
                    store.sessionToolCalls[sessionId]?[executionId] = toolData
                }
            }

        case .agentExecutionCompleted(let run, _):
            // Write model/tool calls for THIS run only
            // Combine API model calls and tool calls for this session, sort by time
            struct Event {
                let timestamp: Date
                let type: EventType
                enum EventType {
                    case apiModelCall(APIModelCallData)
                    case toolCall(ToolCallData)
                }
            }

            let (_, runDir, events) =
                store.withValue { store -> (URL, URL, [Event])? in
                    guard let sessionDir = store.sessionDirectories[run.sessionId] else { return nil }
                    let sessionId = run.sessionId

                    let counter = store.runCounters[sessionId] ?? 1
                    let runDirName = String(format: "run-%03d", counter)
                    let runDir = sessionDir.appendingPathComponent(runDirName)
                    try? fileManager.createDirectory(at: runDir, withIntermediateDirectories: true)
                    store.runDirectories[run.id] = runDir
                    store.fileCounters[run.id] = 0

                    var events: [Event] = []
                    if let apiCalls = store.sessionAPIModelCalls[sessionId] {
                        events += apiCalls.values.map { Event(timestamp: $0.startTime, type: .apiModelCall($0)) }
                    }
                    if let toolCalls = store.sessionToolCalls[sessionId] {
                        events += toolCalls.values.map { Event(timestamp: $0.startTime, type: .toolCall($0)) }
                    }
                    events.sort { $0.timestamp < $1.timestamp }

                    return (sessionDir, runDir, events)
                } ?? (URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/"), [])

            guard !events.isEmpty else { return }

            // Write all files in chronological order
            for event in events {
                switch event.type {
                case .apiModelCall(let callData):
                    guard let response = callData.responseContent,
                        let duration = callData.duration,
                        let responseTime = callData.responseTime
                    else { continue }

                    writeAPIModelCallFile(
                        runDir: runDir,
                        runId: run.id,
                        callData: callData,
                        response: response,
                        duration: duration,
                        inputTokens: callData.inputTokens,
                        outputTokens: callData.outputTokens,
                        timestamp: responseTime
                    )

                case .toolCall(let toolData):
                    guard let result = toolData.result,
                        let duration = toolData.duration,
                        let endTime = toolData.endTime,
                        let success = toolData.success
                    else { continue }

                    writeToolCallFile(
                        runDir: runDir,
                        runId: run.id,
                        toolData: toolData,
                        result: result,
                        duration: duration,
                        success: success,
                        timestamp: endTime
                    )
                }
            }

            // Write summary.json
            let agentId = store.withValue { $0.sessionAgents[run.sessionId] } ?? "unknown"
            writeSummaryFile(runDir: runDir, runId: run.id, sessionId: run.sessionId, agentId: agentId, endTime: event.timestamp)

            // Clean up this session's calls (not all sessions)
            store.withValue { store in
                store.sessionAPIModelCalls[run.sessionId] = nil
                store.sessionToolCalls[run.sessionId] = nil
                store.sessionUserInput[run.sessionId] = nil
                store.sessionFinalResponse[run.sessionId] = nil
                store.sessionStartTime[run.sessionId] = nil
                store.sessionModelName[run.sessionId] = nil
                store.currentRunSession = nil
            }

        default:
            break
        }
    }

    private func writeEventLog(_ event: AgentCenterEvent) {
        let logFile = directory.appendingPathComponent("events.log")
        let timestamp = ISO8601DateFormatter().string(from: event.timestamp)
        let entry = "[\(timestamp)] \(event.description)\n"

        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? entry.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    private func writeAPIModelCallFile(
        runDir: URL,
        runId: UUID,
        callData: APIModelCallData,
        response: String,
        duration: TimeInterval,
        inputTokens: Int?,
        outputTokens: Int?,
        timestamp: Date
    ) {
        let fileNum = store.withValue { store in
            let num = (store.fileCounters[runId] ?? 0) + 1
            store.fileCounters[runId] = num
            return num
        }

        let filename = String(format: "%02d-api-call.md", fileNum)
        let fileURL = runDir.appendingPathComponent(filename)

        let formatter = ISO8601DateFormatter()

        var content = ""
        content += "# API Model Call #\(fileNum)\n\n"
        content += "**Timestamp:** \(formatter.string(from: callData.startTime)) → \(formatter.string(from: timestamp))  \n"
        content += "**Duration:** \(String(format: "%.3f", duration))s  \n"
        content += "\n"

        content += "## Metrics\n\n"
        if let inTokens = inputTokens {
            content += "- **Input Tokens:** \(inTokens)\n"
        }
        if let outTokens = outputTokens {
            content += "- **Output Tokens:** \(outTokens)\n"
        }
        if let inTokens = inputTokens, let outTokens = outputTokens {
            content += "- **Total:** \(inTokens + outTokens) tokens\n"
        }
        content += "\n"

        content += "## Request (Stateless API Call)\n\n"
        content += "_Total transcript entries: \(callData.transcriptEntries.count)_\n\n"

        // Write each transcript entry (these are the exact messages sent to the API)
        var msgNum = 0
        for entry in callData.transcriptEntries {
            msgNum += 1
            switch entry {
            case .instructions(let inst):
                content += "### Message \(msgNum): System\n\n"
                content += extractTextFromInstructions(inst)
                content += "\n"
                if !inst.toolDefinitions.isEmpty {
                    content += "\n**Available Tools:** \(inst.toolDefinitions.count)\n\n"
                    for (idx, tool) in inst.toolDefinitions.enumerated() {
                        content += "\(idx + 1). **\(tool.name)**"
                        let desc = tool.description
                        if !desc.isEmpty {
                            content += " - \(desc)"
                        }
                        content += "\n"
                    }
                }
                content += "\n"

            case .prompt(let prompt):
                content += "### Message \(msgNum): User\n\n"
                content += extractTextFromPrompt(prompt)
                content += "\n\n"

            case .response(let resp):
                content += "### Message \(msgNum): Assistant\n\n"
                content += extractTextFromResponse(resp)
                content += "\n\n"

            case .toolCalls(let toolCalls):
                content += "### Message \(msgNum): Assistant - Tool Calls\n\n"
                for (idx, call) in toolCalls.calls.enumerated() {
                    content += "**Tool Call \(idx + 1):**\n"
                    content += "- **Tool:** `\(call.toolName)`\n"
                    content += "- **Arguments:** `\(call.arguments)`\n"
                    if idx < toolCalls.calls.count - 1 {
                        content += "\n"
                    }
                }
                content += "\n"

            case .toolOutput(let toolOutput):
                content += "### Message \(msgNum): Tool - \(toolOutput.toolName)\n\n"
                // Try to extract text from segments
                var hasContent = false
                for segment in toolOutput.segments {
                    if case .text(let text) = segment {
                        content += "```\n\(text.content)\n```\n"
                        hasContent = true
                    }
                }
                if !hasContent {
                    content += "```\n\(toolOutput)\n```\n"
                }
                content += "\n"
            }
        }

        content += "## Response\n\n"
        content += "**Received:** \(formatter.string(from: timestamp))\n\n"

        if response.isEmpty {
            content += "_Tool call - see next message in transcript_\n"
        } else {
            content += "\(response)\n"
        }

        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // Extract text from transcript segments
    private func extractTextFromInstructions(_ inst: Transcript.Instructions) -> String {
        inst.segments.compactMap { segment in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined(separator: "\n")
    }

    private func extractTextFromPrompt(_ prompt: Transcript.Prompt) -> String {
        prompt.segments.compactMap { segment in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined(separator: "\n")
    }

    private func extractTextFromResponse(_ response: Transcript.Response) -> String {
        response.segments.compactMap { segment in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined(separator: "\n")
    }

    private func sanitizeFilenameComponent(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mappedCharacters: [Character] = input.unicodeScalars.map { scalar in
            if allowed.contains(scalar) {
                return Character(scalar)
            } else {
                return "_"
            }
        }
        var sanitized = String(mappedCharacters)
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        if sanitized.isEmpty {
            sanitized = "tool"
        }
        return sanitized
    }

    private func writeToolCallFile(
        runDir: URL,
        runId: UUID,
        toolData: ToolCallData,
        result: String,
        duration: TimeInterval,
        success: Bool,
        timestamp: Date
    ) {
        let fileNum = store.withValue { store in
            let num = (store.fileCounters[runId] ?? 0) + 1
            store.fileCounters[runId] = num
            return num
        }

        let safeToolName = sanitizeFilenameComponent(toolData.toolName)
        let filename = String(format: "%02d-tool-%@.md", fileNum, safeToolName)
        let fileURL = runDir.appendingPathComponent(filename)

        let formatter = ISO8601DateFormatter()

        var content = ""
        content += "# Tool Execution: \(toolData.toolName)\n\n"
        content += "**Execution ID:** `\(toolData.executionId)`  \n"
        content += "**Timestamp:** \(formatter.string(from: toolData.startTime)) → \(formatter.string(from: timestamp))  \n"
        content += "**Duration:** \(String(format: "%.3f", duration))s  \n"
        content += "**Status:** \(success ? "✅ SUCCESS" : "❌ FAILED")  \n"
        content += "\n"

        content += "## Arguments\n\n"
        content += "```json\n"
        content += toolData.arguments
        content += "\n```\n\n"

        content += "## Result\n\n"
        content += "**Completed:** \(formatter.string(from: timestamp))\n\n"
        content += "```\n"
        content += result
        content += "\n```\n"

        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func writeSummaryFile(runDir: URL, runId: UUID, sessionId: UUID, agentId: String, endTime: Date) {
        let summaryURL = runDir.appendingPathComponent("summary.json")

        let (userInput, finalResponse, startTime, modelName, eventSummaries) = store.withValue { store -> (String, String, Date, String, [(String, String, Date, TimeInterval?, Int?, Int?, Bool?)]) in
            let userInput = store.sessionUserInput[sessionId] ?? ""
            let finalResponse = store.sessionFinalResponse[sessionId] ?? ""
            let startTime = store.sessionStartTime[sessionId] ?? Date()
            let modelName = store.sessionModelName[sessionId] ?? "unknown"

            // Build event summaries from API calls and tool calls
            var events: [(String, String, Date, TimeInterval?, Int?, Int?, Bool?)] = []

            // Add API calls
            if let apiCalls = store.sessionAPIModelCalls[sessionId] {
                for callData in apiCalls.values {
                    // Find the file number by matching with written files
                    events.append(
                        (
                            "apiCall",
                            "",  // Will determine filename later
                            callData.startTime,
                            callData.duration,
                            callData.inputTokens,
                            callData.outputTokens,
                            nil
                        ))
                }
            }

            // Add tool calls
            if let toolCalls = store.sessionToolCalls[sessionId] {
                for toolData in toolCalls.values {
                    events.append(
                        (
                            "toolCall",
                            toolData.toolName,
                            toolData.startTime,
                            toolData.duration,
                            nil,
                            nil,
                            toolData.success
                        ))
                }
            }

            return (userInput, finalResponse, startTime, modelName, events)
        }

        // Sort events by timestamp
        let sortedEvents = eventSummaries.sorted { $0.2 < $1.2 }

        // Calculate totals
        var totalInputTokens = 0
        var totalOutputTokens = 0
        var totalDuration: TimeInterval = 0
        var apiCallCount = 0
        var toolCallCount = 0

        // Build events JSON array and calculate totals
        var eventsJSON: [[String: Any]] = []
        var fileNumber = 1

        for event in sortedEvents {
            let (type, toolName, timestamp, duration, inputTokens, outputTokens, success) = event

            let filename: String
            if type == "apiCall" {
                filename = String(format: "%02d-api-call.md", fileNumber)
                apiCallCount += 1
                if let inTokens = inputTokens { totalInputTokens += inTokens }
                if let outTokens = outputTokens { totalOutputTokens += outTokens }
            } else {
                let safeToolName = sanitizeFilenameComponent(toolName)
                filename = String(format: "%02d-tool-%@.md", fileNumber, safeToolName)
                toolCallCount += 1
            }

            if let dur = duration { totalDuration += dur }

            var eventDict: [String: Any] = [
                "type": type,
                "file": filename,
                "timestamp": ISO8601DateFormatter().string(from: timestamp),
            ]

            if type == "apiCall" {
                if let inTokens = inputTokens { eventDict["inputTokens"] = inTokens }
                if let outTokens = outputTokens { eventDict["outputTokens"] = outTokens }
            } else {
                eventDict["name"] = toolName
                if let s = success { eventDict["success"] = s }
            }

            if let dur = duration { eventDict["duration"] = Double(round(dur * 1000) / 1000) }

            eventsJSON.append(eventDict)
            fileNumber += 1
        }

        // Calculate actual run duration from first to last event
        let runDuration: TimeInterval
        if let firstTimestamp = sortedEvents.first?.2,
            let lastTimestamp = sortedEvents.last?.2
        {
            runDuration = lastTimestamp.timeIntervalSince(firstTimestamp) + (sortedEvents.last?.3 ?? 0)
        } else {
            runDuration = 0
        }

        // Build summary JSON
        let summary: [String: Any] = [
            "agentId": agentId,
            "sessionId": sessionId.uuidString,
            "userInput": userInput,
            "finalResponse": finalResponse,
            "modelName": modelName,
            "totalInputTokens": totalInputTokens,
            "totalOutputTokens": totalOutputTokens,
            "totalTokens": totalInputTokens + totalOutputTokens,
            "totalDuration": Double(round(runDuration * 1000) / 1000),
            "apiCallCount": apiCallCount,
            "toolCallCount": toolCallCount,
            "startTime": ISO8601DateFormatter().string(from: startTime),
            "endTime": ISO8601DateFormatter().string(from: endTime),
            "events": eventsJSON,
        ]

        // Write JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: summaryURL)
        }
    }
}
