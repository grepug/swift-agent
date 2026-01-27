import AnyLanguageModel
import Foundation

/// Events emitted during agent execution lifecycle
public enum AgentCenterEvent: Sendable {
    // MARK: - Agent Lifecycle

    case agentExecutionStarted(
        agent: Agent,
        session: AgentSessionContext,
        timestamp: Date
    )

    case agentExecutionCompleted(
        run: Run,
        timestamp: Date
    )

    case agentExecutionFailed(
        session: AgentSessionContext,
        error: Error,
        timestamp: Date
    )

    // MARK: - MCP Discovery

    case mcpServerDiscoveryStarted(
        serverNames: [String],
        timestamp: Date
    )

    case mcpServerDiscovered(
        serverName: String,
        toolNames: [String],
        timestamp: Date
    )

    case mcpServerDiscoveryFailed(
        serverName: String,
        error: Error,
        timestamp: Date
    )

    // MARK: - Transcript Building

    case transcriptBuildStarted(
        agentId: String,
        previousRunCount: Int,
        timestamp: Date
    )

    case transcriptBuilt(
        transcript: Transcript,
        agentId: String,
        toolCount: Int,
        timestamp: Date
    )

    // MARK: - Model Interaction

    case modelRequestSending(
        requestId: UUID,
        transcript: Transcript,
        message: String,
        agentId: String,
        modelName: String,
        toolCount: Int,
        timestamp: Date
    )

    case modelResponseReceived(
        requestId: UUID,
        content: String,
        agentId: String,
        sessionId: UUID,
        duration: TimeInterval,
        inputTokens: Int?,
        outputTokens: Int?,
        timestamp: Date
    )

    // MARK: - Tool Execution

    case toolExecutionStarted(
        toolName: String,
        arguments: String,
        executionId: UUID,
        timestamp: Date
    )

    case toolExecutionCompleted(
        executionId: UUID,
        toolName: String,
        result: String,
        duration: TimeInterval,
        success: Bool,
        timestamp: Date
    )

    // MARK: - Session Management

    case sessionCreated(
        agentId: String,
        modelName: String,
        toolCount: Int,
        timestamp: Date
    )

    // MARK: - Storage

    case runSaved(
        runId: UUID,
        agentId: String,
        messageCount: Int,
        timestamp: Date
    )
}

extension AgentCenterEvent {
    /// Human-readable description of the event
    public var description: String {
        switch self {
        case .agentExecutionStarted(let agent, let session, _):
            return "Agent '\(agent.name)' execution started (session: \(session.sessionId))"
        case .agentExecutionCompleted(let run, _):
            return "Agent execution completed (run: \(run.id))"
        case .agentExecutionFailed(let session, let error, _):
            return "Agent execution failed (session: \(session.sessionId)): \(error)"
        case .mcpServerDiscoveryStarted(let servers, _):
            return "MCP server discovery started: \(servers.joined(separator: ", "))"
        case .mcpServerDiscovered(let server, let tools, _):
            return "MCP server '\(server)' discovered \(tools.count) tools: \(tools.joined(separator: ", "))"
        case .mcpServerDiscoveryFailed(let server, let error, _):
            return "MCP server '\(server)' discovery failed: \(error)"
        case .transcriptBuildStarted(let agentId, let count, _):
            return "Building transcript for agent \(agentId) with \(count) previous runs"
        case .transcriptBuilt(_, let agentId, let toolCount, _):
            return "Transcript built for agent \(agentId) with \(toolCount) tools"
        case .modelRequestSending(let reqId, _, let message, let agentId, let model, let toolCount, _):
            return "Sending to model '\(model)' (req: \(reqId), agent: \(agentId), tools: \(toolCount)): \(message.prefix(50))..."
        case .modelResponseReceived(let reqId, let content, let agentId, _, let duration, let inTokens, let outTokens, _):
            let tokens = [inTokens.map { "\($0) in" }, outTokens.map { "\($0) out" }].compactMap { $0 }.joined(separator: ", ")
            return "Response received (req: \(reqId), agent: \(agentId), duration: \(String(format: "%.3f", duration))s\(tokens.isEmpty ? "" : ", tokens: \(tokens)")): \(content.prefix(50))..."
        case .toolExecutionStarted(let tool, _, let execId, _):
            return "Tool execution started: \(tool) (exec: \(execId))"
        case .toolExecutionCompleted(let execId, let tool, _, let duration, let success, _):
            return "Tool execution \(success ? "completed" : "failed"): \(tool) (exec: \(execId), duration: \(String(format: "%.3f", duration))s)"
        case .sessionCreated(let agentId, let model, let toolCount, _):
            return "Session created for agent \(agentId) with model '\(model)' and \(toolCount) tools"
        case .runSaved(let runId, let agentId, let messageCount, _):
            return "Run \(runId) saved for agent \(agentId) with \(messageCount) messages"
        }
    }

    /// Timestamp of when the event occurred
    public var timestamp: Date {
        switch self {
        case .agentExecutionStarted(_, _, let timestamp),
            .agentExecutionCompleted(_, let timestamp),
            .agentExecutionFailed(_, _, let timestamp),
            .mcpServerDiscoveryStarted(_, let timestamp),
            .mcpServerDiscovered(_, _, let timestamp),
            .mcpServerDiscoveryFailed(_, _, let timestamp),
            .transcriptBuildStarted(_, _, let timestamp),
            .transcriptBuilt(_, _, _, let timestamp),
            .modelRequestSending(_, _, _, _, _, _, let timestamp),
            .modelResponseReceived(_, _, _, _, _, _, _, let timestamp),
            .toolExecutionStarted(_, _, _, let timestamp),
            .toolExecutionCompleted(_, _, _, _, _, let timestamp),
            .sessionCreated(_, _, _, let timestamp),
            .runSaved(_, _, _, let timestamp):
            return timestamp
        }
    }
}
