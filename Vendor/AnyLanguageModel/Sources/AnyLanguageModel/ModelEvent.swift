import Foundation

/// Events emitted during language model operations.
///
/// Model events provide comprehensive information about requests and responses,
/// including timing, token usage, and complete API response data. Events are
/// emitted through a callback handler for monitoring and debugging.
///
/// ```swift
/// session.onEvent = { event in
///     if case .requestCompleted(let info) = event.details {
///         print("Used \(info.tokenUsage?.totalTokens ?? 0) tokens")
///         print("Duration: \(info.duration)s")
///     }
/// }
/// ```
public struct ModelEvent: Sendable {
    /// Unique identifier for this event.
    public let id: UUID

    /// When the event occurred.
    public let timestamp: Date

    /// Identifier of the model that generated this event (e.g., "gpt-4o-mini").
    public let modelIdentifier: String

    /// Unique identifier of the session.
    public let sessionID: UUID

    /// Detailed information about the event.
    public let details: EventDetails

    /// Creates a new model event.
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        modelIdentifier: String,
        sessionID: UUID,
        details: EventDetails
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelIdentifier = modelIdentifier
        self.sessionID = sessionID
        self.details = details
    }

    /// Detailed event information.
    public enum EventDetails: Sendable {
        /// A request to the model has started.
        case requestStarted(RequestStartedInfo)

        /// A request to the model has completed successfully.
        case requestCompleted(RequestCompletedInfo)

        /// A request to the model has failed.
        case requestFailed(RequestFailedInfo)

        /// A streaming response has started.
        case streamingStarted(StreamingStartedInfo)

        /// A chunk of streaming data was received.
        case streamingChunk(StreamingChunkInfo)

        /// A streaming response has completed.
        case streamingCompleted(StreamingCompletedInfo)

        /// A tool call has started.
        case toolCallStarted(ToolCallStartedInfo)

        /// A tool call has completed successfully.
        case toolCallCompleted(ToolCallCompletedInfo)

        /// A tool call has failed.
        case toolCallFailed(ToolCallFailedInfo)
    }

    /// Information about a request that has started.
    public struct RequestStartedInfo: Sendable {
        /// A summary description of this request.
        /// For complete message context, use `transcriptEntries`.
        public let promptText: String

        /// Generation options used for the request.
        public let options: GenerationOptions

        /// Complete transcript entries being sent in this request.
        /// This includes all conversation history, instructions, and the current prompt.
        public let transcriptEntries: [Transcript.Entry]

        /// Tools available for this request.
        public let availableTools: [String]

        /// Creates request started info.
        public init(
            promptText: String,
            options: GenerationOptions,
            transcriptEntries: [Transcript.Entry],
            availableTools: [String]
        ) {
            self.promptText = promptText
            self.options = options
            self.transcriptEntries = transcriptEntries
            self.availableTools = availableTools
        }
    }

    /// Comprehensive information about a completed request.
    public struct RequestCompletedInfo: Sendable {
        /// How long the request took to complete.
        public let duration: TimeInterval

        /// The generated content.
        public let content: String

        /// Length of the generated content in characters.
        public let contentLength: Int

        /// Token usage for this request.
        public let tokenUsage: TokenUsage?

        /// Complete response metadata from the API.
        public let metadata: ResponseMetadata?

        /// Finish reason if provided by the API.
        public let finishReason: String?

        /// Model-specific response data (provider-dependent).
        public let providerResponseData: [String: String]?

        /// Creates request completed info.
        public init(
            duration: TimeInterval,
            content: String,
            contentLength: Int,
            tokenUsage: TokenUsage?,
            metadata: ResponseMetadata?,
            finishReason: String? = nil,
            providerResponseData: [String: String]? = nil
        ) {
            self.duration = duration
            self.content = content
            self.contentLength = contentLength
            self.tokenUsage = tokenUsage
            self.metadata = metadata
            self.finishReason = finishReason
            self.providerResponseData = providerResponseData
        }
    }

    /// Information about a failed request.
    public struct RequestFailedInfo: Sendable {
        /// How long before the request failed.
        public let duration: TimeInterval

        /// The error that occurred.
        public let errorDescription: String

        /// Creates request failed info.
        public init(duration: TimeInterval, errorDescription: String) {
            self.duration = duration
            self.errorDescription = errorDescription
        }
    }

    /// Information about a streaming response that has started.
    public struct StreamingStartedInfo: Sendable {
        /// The prompt text sent to the model.
        public let promptText: String

        /// Generation options used for the request.
        public let options: GenerationOptions

        /// Complete transcript entries being sent in this request.
        public let transcriptEntries: [Transcript.Entry]

        /// Tools available for this request.
        public let availableTools: [String]

        /// Creates streaming started info.
        public init(
            promptText: String,
            options: GenerationOptions,
            transcriptEntries: [Transcript.Entry],
            availableTools: [String]
        ) {
            self.promptText = promptText
            self.options = options
            self.transcriptEntries = transcriptEntries
            self.availableTools = availableTools
        }
    }

    /// Information about a streaming chunk.
    public struct StreamingChunkInfo: Sendable {
        /// Size of this chunk in characters.
        public let chunkSize: Int

        /// Cumulative size of all chunks so far.
        public let cumulativeSize: Int

        /// Time elapsed since streaming started.
        public let elapsedTime: TimeInterval

        /// Creates streaming chunk info.
        public init(chunkSize: Int, cumulativeSize: Int, elapsedTime: TimeInterval) {
            self.chunkSize = chunkSize
            self.cumulativeSize = cumulativeSize
            self.elapsedTime = elapsedTime
        }
    }

    /// Comprehensive information about a completed streaming response.
    public struct StreamingCompletedInfo: Sendable {
        /// Total duration of the streaming response.
        public let duration: TimeInterval

        /// Complete generated content.
        public let content: String

        /// Total size of the response in characters.
        public let totalSize: Int

        /// Number of chunks received.
        public let chunkCount: Int

        /// Token usage for the streaming request.
        public let tokenUsage: TokenUsage?

        /// Complete response metadata from the API.
        public let metadata: ResponseMetadata?

        /// Finish reason if provided by the API.
        public let finishReason: String?

        /// Creates streaming completed info.
        public init(
            duration: TimeInterval,
            content: String,
            totalSize: Int,
            chunkCount: Int,
            tokenUsage: TokenUsage?,
            metadata: ResponseMetadata?,
            finishReason: String? = nil
        ) {
            self.duration = duration
            self.content = content
            self.totalSize = totalSize
            self.chunkCount = chunkCount
            self.tokenUsage = tokenUsage
            self.metadata = metadata
            self.finishReason = finishReason
        }
    }

    /// Information about a tool call that has started.
    public struct ToolCallStartedInfo: Sendable {
        /// Name of the tool being called.
        public let toolName: String

        /// Arguments passed to the tool (JSON serialized).
        public let arguments: String

        /// Index of this call in the sequence (for multi-tool scenarios).
        public let callIndex: Int

        /// Creates tool call started info.
        public init(toolName: String, arguments: String, callIndex: Int) {
            self.toolName = toolName
            self.arguments = arguments
            self.callIndex = callIndex
        }
    }

    /// Information about a completed tool call.
    public struct ToolCallCompletedInfo: Sendable {
        /// Name of the tool that was called.
        public let toolName: String

        /// How long the tool execution took.
        public let duration: TimeInterval

        /// Result returned by the tool (serialized).
        public let result: String

        /// Index of this call in the sequence.
        public let callIndex: Int

        /// Creates tool call completed info.
        public init(toolName: String, duration: TimeInterval, result: String, callIndex: Int) {
            self.toolName = toolName
            self.duration = duration
            self.result = result
            self.callIndex = callIndex
        }
    }

    /// Information about a failed tool call.
    public struct ToolCallFailedInfo: Sendable {
        /// Name of the tool that failed.
        public let toolName: String

        /// How long before the tool failed.
        public let duration: TimeInterval

        /// Description of the error that occurred.
        public let errorDescription: String

        /// Index of this call in the sequence.
        public let callIndex: Int

        /// Creates tool call failed info.
        public init(toolName: String, duration: TimeInterval, errorDescription: String, callIndex: Int) {
            self.toolName = toolName
            self.duration = duration
            self.errorDescription = errorDescription
            self.callIndex = callIndex
        }
    }
}
