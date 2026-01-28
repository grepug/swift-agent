import AnyLanguageModel
import Foundation

extension FileDebugObserver {
    func writeAPICallFile(_ data: ModelCallData, to directory: URL, number: Int) {
        let filename = String(format: "%02d-api-call.md", number)
        let file = directory.appendingPathComponent(filename)

        let duration = data.duration.map { String(format: "%.3f", $0) } ?? "pending"
        let inputTokens = data.inputTokens.map { String($0) } ?? "n/a"
        let outputTokens = data.outputTokens.map { String($0) } ?? "n/a"
        let totalTokens =
            (data.inputTokens != nil && data.outputTokens != nil)
            ? String((data.inputTokens ?? 0) + (data.outputTokens ?? 0))
            : "n/a"

        var content = """
            # API Call: \(data.modelName)

            **Request ID:** \(data.requestId.uuidString)
            **Start Time:** \(ISO8601DateFormatter().string(from: data.startTime))
            **Duration:** \(duration)s
            **Input Tokens:** \(inputTokens)
            **Output Tokens:** \(outputTokens)
            **Total Tokens:** \(totalTokens)

            ## Request Message

            ```
            \(data.message)
            ```

            ## Transcript

            ```
            \(transcriptToString(data.transcript))
            ```

            """

        if let response = data.responseContent {
            content += """
                ## Response

                ```
                \(response)
                ```

                """
        }

        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    private func transcriptToString(_ transcript: Transcript) -> String {
        var result = ""
        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                let content = instructions.segments.map { segmentToString($0) }.joined(separator: "\n")
                result += "[Instructions] \(instructions.segments.count) segments, \(instructions.toolDefinitions.count) tools\n\n\(content)\n\n"

                // Add tool definitions
                if !instructions.toolDefinitions.isEmpty {
                    result += "## Available Tools (\(instructions.toolDefinitions.count))\n\n"
                    for (index, toolDef) in instructions.toolDefinitions.enumerated() {
                        result += "\(index + 1). **\(toolDef.name)**: \(toolDef.description)\n"
                    }
                    result += "\n"
                }
            case .prompt(let prompt):
                let content = prompt.segments.map { segmentToString($0) }.joined(separator: " ")
                result += "[Prompt] \(content)\n\n"
            case .toolCalls(let toolCalls):
                result += "[ToolCalls] \(toolCalls.calls.map { $0.toolName }.joined(separator: ", "))\n\n"
            case .toolOutput(let toolOutput):
                let content = toolOutput.segments.map { segmentToString($0) }.joined(separator: " ")
                result += "[ToolOutput: \(toolOutput.toolName)] \(content)\n\n"
            case .response(let response):
                let content = response.segments.map { segmentToString($0) }.joined(separator: " ")
                result += "[Response] \(content)\n\n"
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func segmentToString(_ segment: Transcript.Segment) -> String {
        switch segment {
        case .text(let textSegment):
            return textSegment.content
        case .structure(let structuredSegment):
            return "<structured: \(structuredSegment.source)>"
        case .image:
            return "<image>"
        case .toolCalls(let toolCallsSegment):
            return "<tool-calls: \(toolCallsSegment.calls.count) calls>"
        }
    }

    func writeToolCallFile(_ data: ToolCallData, to directory: URL, number: Int) {
        let sanitizedToolName = sanitizeFilenameComponent(data.toolName)
        let filename = String(format: "%02d-tool-%@.md", number, sanitizedToolName)
        let file = directory.appendingPathComponent(filename)

        let duration = data.duration.map { String(format: "%.3f", $0) } ?? "pending"
        let success = data.success.map { $0 ? "✅" : "❌" } ?? "⏳"

        var content = """
            # Tool Execution: \(data.toolName)

            **Execution ID:** \(data.executionId.uuidString)
            **Start Time:** \(ISO8601DateFormatter().string(from: data.startTime))
            **Duration:** \(duration)s
            **Status:** \(success)

            ## Arguments

            ```json
            \(data.arguments)
            ```

            """

        if let result = data.result {
            content += """
                ## Result

                ```
                \(result)
                ```

                """
        }

        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    func writeSummaryFile(
        to directory: URL,
        sessionId: UUID,
        agentId: String,
        userInput: String?,
        finalResponse: String?,
        modelName: String?,
        startTime: Date?,
        endTime: Date,
        inputTokens: Int?,
        outputTokens: Int?
    ) {
        let file = directory.appendingPathComponent("summary.json")

        let duration = startTime.map { endTime.timeIntervalSince($0) }

        let summary: [String: Any?] = [
            "agentId": agentId,
            "sessionId": sessionId.uuidString,
            "userInput": userInput,
            "finalResponse": finalResponse,
            "modelName": modelName,
            "startTime": startTime.map { ISO8601DateFormatter().string(from: $0) },
            "endTime": ISO8601DateFormatter().string(from: endTime),
            "duration": duration,
            "inputTokens": inputTokens,
            "outputTokens": outputTokens,
        ]

        // Filter out nil values
        let cleanSummary = summary.compactMapValues { $0 }

        if let jsonData = try? JSONSerialization.data(
            withJSONObject: cleanSummary,
            options: [.prettyPrinted, .sortedKeys]
        ),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            try? jsonString.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
