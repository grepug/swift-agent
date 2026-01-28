import AnyLanguageModel
import Foundation

extension FileDebugObserver {
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
