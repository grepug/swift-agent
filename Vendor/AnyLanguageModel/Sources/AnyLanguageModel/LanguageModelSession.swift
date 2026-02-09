import Foundation
import Observation

@Observable
public final class LanguageModelSession: @unchecked Sendable {
    public private(set) var isResponding: Bool = false
    public private(set) var transcript: Transcript
    public private(set) var cumulativeUsage: TokenUsage?

    /// Unique identifier for this session.
    public let sessionID: UUID

    /// Optional callback invoked for each event.
    public var onEvent: (@Sendable (ModelEvent) -> Void)?

    private let model: any LanguageModel
    public let tools: [any Tool]
    public let instructions: Instructions?

    @ObservationIgnored private let respondingState = RespondingState()

    public convenience init(
        model: any LanguageModel,
        tools: [any Tool] = [],
        @InstructionsBuilder instructions: () throws -> Instructions
    ) rethrows {
        try self.init(model: model, tools: tools, instructions: instructions())
    }

    public convenience init(
        model: any LanguageModel,
        tools: [any Tool] = [],
        instructions: String
    ) {
        self.init(model: model, tools: tools, instructions: Instructions(instructions), transcript: Transcript())
    }

    public convenience init(
        model: any LanguageModel,
        tools: [any Tool] = [],
        instructions: Instructions? = nil
    ) {
        self.init(model: model, tools: tools, instructions: instructions, transcript: Transcript())
    }

    public convenience init(
        model: any LanguageModel,
        tools: [any Tool] = [],
        transcript: Transcript
    ) {
        self.init(model: model, tools: tools, instructions: nil, transcript: transcript)
    }

    private init(
        model: any LanguageModel,
        tools: [any Tool],
        instructions: Instructions?,
        transcript: Transcript
    ) {
        self.model = model
        self.tools = tools
        self.instructions = instructions
        self.sessionID = UUID()

        // Build transcript with instructions if provided and not already in transcript
        var finalTranscript = transcript
        if let instructions = instructions {
            // Only add instructions if transcript doesn't already start with instructions
            let hasInstructions =
                finalTranscript.first.map { entry in
                    if case .instructions = entry { return true } else { return false }
                } ?? false

            if !hasInstructions {
                let instructionsEntry = Transcript.Entry.instructions(
                    Transcript.Instructions(
                        segments: [.text(.init(content: instructions.description))],
                        toolDefinitions: tools.map { Transcript.ToolDefinition(tool: $0) }
                    )
                )
                finalTranscript.append(instructionsEntry)
            }
        }

        self.transcript = finalTranscript
    }

    public func prewarm(promptPrefix: Prompt? = nil) {
        model.prewarm(for: self, promptPrefix: promptPrefix)
    }

    /// Emits an event by calling the callback handler.
    nonisolated private func emitEvent(_ event: ModelEvent) {
        onEvent?(event)
    }

    /// Gets the model identifier for event emission.
    nonisolated private func modelIdentifier() -> String {
        // Try to extract model name from various model types
        if let openAI = model as? OpenAILanguageModel {
            return openAI.model
        }
        return String(describing: type(of: model))
    }

    /// Execute a tool call with event emission.
    ///
    /// This method wraps tool execution with events for monitoring and debugging.
    /// It should be called by language model implementations when executing tools.
    ///
    /// - Parameters:
    ///   - tool: The tool to execute
    ///   - arguments: Arguments as GeneratedContent
    ///   - callIndex: Index of this call in the sequence (for multi-tool scenarios)
    /// - Returns: Array of output segments from the tool
    /// - Throws: Any error thrown by the tool
    nonisolated internal func executeToolWithEvents(
        _ tool: any Tool,
        arguments: GeneratedContent,
        callIndex: Int
    ) async throws -> [Transcript.Segment] {
        let modelID = modelIdentifier()
        let startTime = Date()

        // Emit tool call started event
        emitEvent(
            ModelEvent(
                modelIdentifier: modelID,
                sessionID: sessionID,
                details: .toolCallStarted(
                    ModelEvent.ToolCallStartedInfo(
                        toolName: tool.name,
                        arguments: arguments.jsonString,
                        callIndex: callIndex
                    )
                )
            )
        )

        do {
            let segments = try await tool.makeOutputSegments(from: arguments)
            let duration = Date().timeIntervalSince(startTime)

            // Serialize result
            let result: String
            if segments.count == 1, case .text(let text) = segments[0] {
                result = text.content
            } else if segments.count == 1, case .structure(let structured) = segments[0] {
                result = structured.content.jsonString
            } else {
                // Multiple segments or mixed types - serialize as JSON array
                result =
                    segments.map { segment in
                        switch segment {
                        case .text(let text): return text.content
                        case .structure(let structured): return structured.content.jsonString
                        case .image: return "[image]"
                        case .toolCalls(let toolCallsSegment): return "[\(toolCallsSegment.calls.count) tool calls]"
                        }
                    }.description
            }

            // Emit tool call completed event
            emitEvent(
                ModelEvent(
                    modelIdentifier: modelID,
                    sessionID: sessionID,
                    details: .toolCallCompleted(
                        ModelEvent.ToolCallCompletedInfo(
                            toolName: tool.name,
                            duration: duration,
                            result: result,
                            callIndex: callIndex
                        )
                    )
                )
            )

            return segments
        } catch {
            let duration = Date().timeIntervalSince(startTime)

            // Emit tool call failed event
            emitEvent(
                ModelEvent(
                    modelIdentifier: modelID,
                    sessionID: sessionID,
                    details: .toolCallFailed(
                        ModelEvent.ToolCallFailedInfo(
                            toolName: tool.name,
                            duration: duration,
                            errorDescription: String(describing: error),
                            callIndex: callIndex
                        )
                    )
                )
            )

            throw error
        }
    }

    /// Notify that an API request to the model is about to start.
    ///
    /// Model implementations should call this before each actual HTTP request to the API.
    /// This ensures requestStarted events are emitted for every API call, including
    /// follow-up calls for tool execution.
    ///
    /// - Parameters:
    ///   - transcriptEntries: The complete transcript entries being sent in this specific API request
    ///   - options: Generation options being used for this request
    ///   - messages: The number of messages being sent to the API (optional, for logging)
    /// - Returns: The event ID that should be passed to `notifyAPIRequestCompleted` to correlate events
    @discardableResult
    nonisolated internal func notifyAPIRequestStarted(
        transcriptEntries: [Transcript.Entry],
        options: GenerationOptions,
        messages: Int = 0
    ) -> UUID {
        let modelID = modelIdentifier()
        let toolNames = tools.map { $0.name }
        let eventID = UUID()

        emitEvent(
            ModelEvent(
                id: eventID,
                modelIdentifier: modelID,
                sessionID: sessionID,
                details: .requestStarted(
                    ModelEvent.RequestStartedInfo(
                        promptText: "(API call with \(messages) messages)",
                        options: options,
                        transcriptEntries: transcriptEntries,
                        availableTools: toolNames
                    )
                )
            )
        )

        return eventID
    }

    /// Notify that an API request to the model has completed.
    ///
    /// Model implementations should call this after each successful API response.
    ///
    /// - Parameters:
    ///   - eventID: The event ID returned from `notifyAPIRequestStarted` to correlate start/complete events
    ///   - duration: How long the API call took
    ///   - content: The response content
    ///   - tokenUsage: Token usage from the API
    ///   - metadata: Response metadata
    nonisolated internal func notifyAPIRequestCompleted(
        eventID: UUID,
        duration: TimeInterval,
        content: String,
        tokenUsage: TokenUsage?,
        metadata: ResponseMetadata?
    ) {
        let modelID = modelIdentifier()

        emitEvent(
            ModelEvent(
                id: eventID,
                modelIdentifier: modelID,
                sessionID: sessionID,
                details: .requestCompleted(
                    ModelEvent.RequestCompletedInfo(
                        duration: duration,
                        content: content,
                        contentLength: content.count,
                        tokenUsage: tokenUsage,
                        metadata: metadata,
                        finishReason: nil,
                        providerResponseData: nil
                    )
                )
            )
        )
    }

    nonisolated private func beginResponding() async {
        let count = await respondingState.increment()
        let active = count > 0
        await MainActor.run {
            self.isResponding = active
        }
    }

    nonisolated private func endResponding() async {
        let count = await respondingState.decrement()
        let active = count > 0
        await MainActor.run {
            self.isResponding = active
        }
    }

    nonisolated private func wrapRespond<T>(_ operation: () async throws -> T) async throws -> T {
        await beginResponding()
        do {
            let result = try await operation()
            await endResponding()
            return result
        } catch {
            await endResponding()
            throw error
        }
    }

    nonisolated private func wrapStream<Content>(
        _ upstream: sending ResponseStream<Content>,
        promptEntry: Transcript.Entry,
        startTime: Date,
        modelID: String
    ) -> ResponseStream<Content> where Content: Generable, Content.PartiallyGenerated: Sendable {
        let session = self
        let relay = AsyncThrowingStream<ResponseStream<Content>.Snapshot, any Error> { continuation in
            let stream = upstream
            Task {
                await session.beginResponding()
                var lastSnapshot: ResponseStream<Content>.Snapshot?
                var chunkCount = 0
                var previousSize = 0

                do {
                    for try await snapshot in stream {
                        lastSnapshot = snapshot
                        continuation.yield(snapshot)

                        // Emit streaming chunk event
                        chunkCount += 1
                        let currentSize: Int
                        if case .string(let str) = snapshot.rawContent.kind {
                            currentSize = str.count
                        } else {
                            currentSize = snapshot.rawContent.jsonString.count
                        }

                        let chunkSize = currentSize - previousSize
                        previousSize = currentSize

                        session.emitEvent(
                            ModelEvent(
                                modelIdentifier: modelID,
                                sessionID: session.sessionID,
                                details: .streamingChunk(
                                    ModelEvent.StreamingChunkInfo(
                                        chunkSize: chunkSize,
                                        cumulativeSize: currentSize,
                                        elapsedTime: Date().timeIntervalSince(startTime)
                                    )
                                )
                            )
                        )
                    }
                    continuation.finish()

                    // Add response to transcript after stream completes
                    if let lastSnapshot {
                        // Extract text content from the generated content
                        let textContent: String
                        if case .string(let str) = lastSnapshot.rawContent.kind {
                            textContent = str
                        } else {
                            textContent = lastSnapshot.rawContent.jsonString
                        }

                        let responseEntry = Transcript.Entry.response(
                            Transcript.Response(
                                assetIDs: [],
                                segments: [.text(.init(content: textContent))]
                            )
                        )
                        await MainActor.run {
                            session.transcript.append(responseEntry)
                        }

                        // Emit streaming completed event
                        let duration = Date().timeIntervalSince(startTime)
                        session.emitEvent(
                            ModelEvent(
                                modelIdentifier: modelID,
                                sessionID: session.sessionID,
                                details: .streamingCompleted(
                                    ModelEvent.StreamingCompletedInfo(
                                        duration: duration,
                                        content: textContent,
                                        totalSize: textContent.count,
                                        chunkCount: chunkCount,
                                        tokenUsage: nil,  // Streaming doesn't always have usage
                                        metadata: nil
                                    )
                                )
                            )
                        )
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
                await session.endResponding()
            }
        }
        return ResponseStream(stream: relay)
    }

    public struct Response<Content>: Sendable where Content: Generable, Content: Sendable {
        public let content: Content
        public let rawContent: GeneratedContent
        public let transcriptEntries: ArraySlice<Transcript.Entry>
        public let metadata: ResponseMetadata?
    }

    @discardableResult
    nonisolated public func respond<Content>(
        to prompt: Prompt,
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<Content> where Content: Generable {
        let startTime = Date()
        let modelID = modelIdentifier()

        do {
            let response = try await wrapRespond {
                // Add prompt to transcript
                let promptEntry = Transcript.Entry.prompt(
                    Transcript.Prompt(
                        segments: [.text(.init(content: prompt.description))],
                        options: options,
                        responseFormat: nil
                    )
                )
                await MainActor.run {
                    self.transcript.append(promptEntry)
                }

                // Note: requestStarted events are now emitted by model implementations
                // for each actual API call, not just once here

                let response = try await model.respond(
                    within: self,
                    to: prompt,
                    generating: type,
                    includeSchemaInPrompt: includeSchemaInPrompt,
                    options: options
                )

                // Add response entry to transcript
                let textContent: String
                if case .string(let str) = response.rawContent.kind {
                    textContent = str
                } else {
                    textContent = response.rawContent.jsonString
                }

                let responseEntry = Transcript.Entry.response(
                    Transcript.Response(
                        assetIDs: [],
                        segments: [.text(.init(content: textContent))]
                    )
                )

                // Add tool entries and response to transcript
                await MainActor.run {
                    self.transcript.append(contentsOf: response.transcriptEntries)
                    self.transcript.append(responseEntry)

                    // Accumulate usage if available
                    if let usage = response.metadata?.tokenUsage {
                        if let existing = self.cumulativeUsage {
                            self.cumulativeUsage = existing + usage
                        } else {
                            self.cumulativeUsage = usage
                        }
                    }
                }

                return response
            }

            // Emit request completed event
            let duration = Date().timeIntervalSince(startTime)
            let contentText: String
            if case .string(let str) = response.rawContent.kind {
                contentText = str
            } else {
                contentText = response.rawContent.jsonString
            }

            emitEvent(
                ModelEvent(
                    modelIdentifier: modelID,
                    sessionID: sessionID,
                    details: .requestCompleted(
                        ModelEvent.RequestCompletedInfo(
                            duration: duration,
                            content: contentText,
                            contentLength: contentText.count,
                            tokenUsage: response.metadata?.tokenUsage,
                            metadata: response.metadata
                        )
                    )
                )
            )

            return response
        } catch {
            // Emit request failed event
            let duration = Date().timeIntervalSince(startTime)
            emitEvent(
                ModelEvent(
                    modelIdentifier: modelID,
                    sessionID: sessionID,
                    details: .requestFailed(
                        ModelEvent.RequestFailedInfo(
                            duration: duration,
                            errorDescription: String(describing: error)
                        )
                    )
                )
            )
            throw error
        }
    }

    nonisolated public func streamResponse<Content>(
        to prompt: Prompt,
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<Content> where Content: Generable {
        let startTime = Date()
        let modelID = modelIdentifier()

        // Add prompt to transcript
        let promptEntry = Transcript.Entry.prompt(
            Transcript.Prompt(
                segments: [.text(.init(content: prompt.description))],
                options: options,
                responseFormat: nil
            )
        )
        transcript.append(promptEntry)

        // Emit streaming started event with complete context
        let toolNames = tools.map { $0.name }
        emitEvent(
            ModelEvent(
                modelIdentifier: modelID,
                sessionID: sessionID,
                details: .streamingStarted(
                    ModelEvent.StreamingStartedInfo(
                        promptText: prompt.description,
                        options: options,
                        transcriptEntries: Array(transcript),
                        availableTools: toolNames
                    )
                )
            )
        )

        return wrapStream(
            model.streamResponse(
                within: self,
                to: prompt,
                generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt,
                options: options
            ),
            promptEntry: promptEntry,
            startTime: startTime,
            modelID: modelID
        )
    }
}

// MARK: - String Response Convenience Methods

extension LanguageModelSession {
    @discardableResult
    nonisolated public func respond(
        to prompt: Prompt,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<String> {
        try await respond(
            to: prompt,
            generating: String.self,
            includeSchemaInPrompt: true,
            options: options
        )
    }

    @discardableResult
    nonisolated public func respond(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<String> {
        try await respond(to: Prompt(prompt), options: options)
    }

    @discardableResult
    nonisolated public func respond(
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: () throws -> Prompt
    ) async throws -> Response<String> {
        try await respond(to: try prompt(), options: options)
    }

    public func streamResponse(
        to prompt: Prompt,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<String> {
        streamResponse(
            to: prompt,
            generating: String.self,
            includeSchemaInPrompt: true,
            options: options
        )
    }

    public func streamResponse(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<String> {
        streamResponse(to: Prompt(prompt), options: options)
    }

    public func streamResponse(
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: () throws -> Prompt
    ) rethrows -> sending ResponseStream<String> {
        streamResponse(to: try prompt(), options: options)
    }
}

// MARK: - GeneratedContent with Schema Convenience Methods

extension LanguageModelSession {
    @discardableResult
    nonisolated public func respond(
        to prompt: Prompt,
        schema: GenerationSchema,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<GeneratedContent> {
        try await respond(
            to: prompt,
            generating: GeneratedContent.self,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    @discardableResult
    nonisolated public func respond(
        to prompt: String,
        schema: GenerationSchema,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<GeneratedContent> {
        try await respond(
            to: Prompt(prompt),
            schema: schema,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    @discardableResult
    nonisolated public func respond(
        schema: GenerationSchema,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: () throws -> Prompt
    ) async throws -> Response<GeneratedContent> {
        try await respond(
            to: try prompt(),
            schema: schema,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    nonisolated public func streamResponse(
        to prompt: Prompt,
        schema: GenerationSchema,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<GeneratedContent> {
        streamResponse(
            to: prompt,
            generating: GeneratedContent.self,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    nonisolated public func streamResponse(
        to prompt: String,
        schema: GenerationSchema,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<GeneratedContent> {
        streamResponse(
            to: Prompt(prompt),
            schema: schema,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    nonisolated public func streamResponse(
        schema: GenerationSchema,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: () throws -> Prompt
    ) rethrows -> sending ResponseStream<GeneratedContent> {
        streamResponse(to: try prompt(), schema: schema, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
    }
}

// MARK: - Generic Content Convenience Methods

extension LanguageModelSession {
    @discardableResult
    nonisolated public func respond<Content>(
        to prompt: String,
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<Content> where Content: Generable {
        try await respond(
            to: Prompt(prompt),
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    @discardableResult
    nonisolated public func respond<Content>(
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: () throws -> Prompt
    ) async throws -> Response<Content> where Content: Generable {
        try await respond(
            to: try prompt(),
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    nonisolated public func streamResponse<Content>(
        to prompt: String,
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<Content> where Content: Generable {
        streamResponse(
            to: Prompt(prompt),
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    public func streamResponse<Content>(
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: () throws -> Prompt
    ) rethrows -> sending ResponseStream<Content> where Content: Generable {
        streamResponse(
            to: try prompt(),
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }
}

// MARK: - Image Convenience Methods

extension LanguageModelSession {
    @discardableResult
    nonisolated public func respond(
        to prompt: String,
        image: Transcript.ImageSegment,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<String> {
        try await respond(
            to: prompt,
            images: [image],
            options: options
        )
    }

    @discardableResult
    nonisolated public func respond(
        to prompt: String,
        images: [Transcript.ImageSegment],
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<String> {
        try await respond(
            to: prompt,
            images: images,
            generating: String.self,
            includeSchemaInPrompt: true,
            options: options
        )
    }

    @discardableResult
    nonisolated public func respond<Content>(
        to prompt: String,
        image: Transcript.ImageSegment,
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<Content> where Content: Generable {
        try await respond(
            to: prompt,
            images: [image],
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    @discardableResult
    nonisolated public func respond<Content>(
        to prompt: String,
        images: [Transcript.ImageSegment],
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> Response<Content> where Content: Generable {
        try await wrapRespond {
            // Build segments from text and images
            var segments: [Transcript.Segment] = []
            if !prompt.isEmpty {
                segments.append(.text(.init(content: prompt)))
            }
            segments.append(contentsOf: images.map { .image($0) })

            // Add prompt to transcript
            let promptEntry = Transcript.Entry.prompt(
                Transcript.Prompt(
                    segments: segments,
                    options: options,
                    responseFormat: nil
                )
            )
            await MainActor.run {
                self.transcript.append(promptEntry)
            }

            // Extract text content for the Prompt parameter
            let textPrompt = Prompt(prompt)

            let response = try await model.respond(
                within: self,
                to: textPrompt,
                generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt,
                options: options
            )

            // Add response entry to transcript
            let textContent: String
            if case .string(let str) = response.rawContent.kind {
                textContent = str
            } else {
                textContent = response.rawContent.jsonString
            }

            let responseEntry = Transcript.Entry.response(
                Transcript.Response(
                    assetIDs: [],
                    segments: [.text(.init(content: textContent))]
                )
            )

            // Add tool entries and response to transcript
            await MainActor.run {
                self.transcript.append(contentsOf: response.transcriptEntries)
                self.transcript.append(responseEntry)

                // Accumulate usage if available
                if let usage = response.metadata?.tokenUsage {
                    if let existing = self.cumulativeUsage {
                        self.cumulativeUsage = existing + usage
                    } else {
                        self.cumulativeUsage = usage
                    }
                }
            }

            return response
        }
    }

    public func streamResponse(
        to prompt: String,
        image: Transcript.ImageSegment,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<String> {
        streamResponse(
            to: prompt,
            images: [image],
            options: options
        )
    }

    public func streamResponse(
        to prompt: String,
        images: [Transcript.ImageSegment],
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<String> {
        streamResponse(
            to: prompt,
            images: images,
            generating: String.self,
            includeSchemaInPrompt: true,
            options: options
        )
    }

    nonisolated public func streamResponse<Content>(
        to prompt: String,
        image: Transcript.ImageSegment,
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<Content> where Content: Generable {
        streamResponse(
            to: prompt,
            images: [image],
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    nonisolated public func streamResponse<Content>(
        to prompt: String,
        images: [Transcript.ImageSegment],
        generating type: Content.Type = Content.self,
        includeSchemaInPrompt: Bool = true,
        options: GenerationOptions = GenerationOptions()
    ) -> sending ResponseStream<Content> where Content: Generable {
        let startTime = Date()
        let modelID = modelIdentifier()

        // Build segments from text and images
        var segments: [Transcript.Segment] = []
        if !prompt.isEmpty {
            segments.append(.text(.init(content: prompt)))
        }
        segments.append(contentsOf: images.map { .image($0) })

        // Create prompt entry that will be added to transcript
        let promptEntry = Transcript.Entry.prompt(
            Transcript.Prompt(
                segments: segments,
                options: options,
                responseFormat: nil
            )
        )
        transcript.append(promptEntry)

        // Emit streaming started event with full context
        let toolNames = tools.map { $0.name }
        emitEvent(
            ModelEvent(
                modelIdentifier: modelID,
                sessionID: sessionID,
                details: .streamingStarted(
                    ModelEvent.StreamingStartedInfo(
                        promptText: prompt,
                        options: options,
                        transcriptEntries: Array(transcript),
                        availableTools: toolNames
                    )
                )
            )
        )

        // Extract text content for the Prompt parameter
        let textPrompt = Prompt(prompt)

        return wrapStream(
            model.streamResponse(
                within: self,
                to: textPrompt,
                generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt,
                options: options
            ),
            promptEntry: promptEntry,
            startTime: startTime,
            modelID: modelID
        )
    }
}

// MARK: -

extension LanguageModelSession {
    @discardableResult
    public func logFeedbackAttachment(
        sentiment: LanguageModelFeedback.Sentiment?,
        issues: [LanguageModelFeedback.Issue] = [],
        desiredOutput: Transcript.Entry? = nil
    ) -> Data {
        model.logFeedbackAttachment(
            within: self,
            sentiment: sentiment,
            issues: issues,
            desiredOutput: desiredOutput
        )
    }
}

// MARK: -

extension LanguageModelSession {
    public enum GenerationError: Error, LocalizedError {
        public struct Context: Sendable {
            public let debugDescription: String

            public init(debugDescription: String) {
                self.debugDescription = debugDescription
            }
        }

        public struct Refusal: Sendable {
            public let transcriptEntries: [Transcript.Entry]

            public init(transcriptEntries: [Transcript.Entry]) {
                self.transcriptEntries = transcriptEntries
            }

            public var explanation: Response<String> {
                get async throws {
                    // Extract explanation from transcript entries
                    let explanationText = transcriptEntries.compactMap { entry in
                        if case .response(let response) = entry {
                            return response.segments.compactMap { segment in
                                if case .text(let textSegment) = segment {
                                    return textSegment.content
                                }
                                return nil
                            }.joined(separator: " ")
                        }
                        return nil
                    }.joined(separator: "\n")

                    return Response(
                        content: explanationText.isEmpty ? "No explanation available" : explanationText,
                        rawContent: GeneratedContent(
                            explanationText.isEmpty ? "No explanation available" : explanationText
                        ),
                        transcriptEntries: ArraySlice(transcriptEntries),
                        metadata: nil
                    )
                }
            }

            public var explanationStream: ResponseStream<String> {
                // Create a simple stream that yields the explanation text
                let explanationText = transcriptEntries.compactMap { entry in
                    if case .response(let response) = entry {
                        return response.segments.compactMap { segment in
                            if case .text(let textSegment) = segment {
                                return textSegment.content
                            }
                            return nil
                        }.joined(separator: " ")
                    }
                    return nil
                }.joined(separator: "\n")

                let finalText = explanationText.isEmpty ? "No explanation available" : explanationText
                return ResponseStream(content: finalText, rawContent: GeneratedContent(finalText))
            }
        }

        case exceededContextWindowSize(Context)
        case assetsUnavailable(Context)
        case guardrailViolation(Context)
        case unsupportedGuide(Context)
        case unsupportedLanguageOrLocale(Context)
        case decodingFailure(Context)
        case rateLimited(Context)
        case concurrentRequests(Context)
        case refusal(Refusal, Context)

        public var errorDescription: String? { nil }
        public var recoverySuggestion: String? { nil }
        public var failureReason: String? { nil }
    }

    public struct ToolCallError: Error, LocalizedError {
        public var tool: any Tool
        public var underlyingError: any Error

        public init(tool: any Tool, underlyingError: any Error) {
            self.tool = tool
            self.underlyingError = underlyingError
        }

        public var errorDescription: String? { nil }
    }
}

extension LanguageModelSession {
    public struct ResponseStream<Content>: Sendable where Content: Generable, Content.PartiallyGenerated: Sendable {
        private let fallbackSnapshot: Snapshot?
        private let streaming: AsyncThrowingStream<Snapshot, any Error>?

        init(content: Content, rawContent: GeneratedContent) {
            self.fallbackSnapshot = Snapshot(content: content.asPartiallyGenerated(), rawContent: rawContent)
            self.streaming = nil
        }

        init(stream: AsyncThrowingStream<Snapshot, any Error>) {
            // When streaming, snapshots arrive from the upstream sequence, so no fallback is required.
            self.fallbackSnapshot = nil
            self.streaming = stream
        }

        public struct Snapshot: Sendable where Content.PartiallyGenerated: Sendable {
            public var content: Content.PartiallyGenerated
            public var rawContent: GeneratedContent
        }
    }
}

extension LanguageModelSession.ResponseStream: AsyncSequence {
    public typealias Element = Snapshot

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var hasYielded = false
        private let fallbackSnapshot: Snapshot?
        private var streamIterator: AsyncThrowingStream<Snapshot, any Error>.AsyncIterator?
        private let useStream: Bool

        init(fallbackSnapshot: Snapshot?, stream: AsyncThrowingStream<Snapshot, any Error>?) {
            self.fallbackSnapshot = fallbackSnapshot
            self.streamIterator = stream?.makeAsyncIterator()
            self.useStream = stream != nil
        }

        public mutating func next() async throws -> Snapshot? {
            if useStream {
                if var iterator = streamIterator {
                    if let value = try await iterator.next() {
                        // store back the advanced iterator
                        streamIterator = iterator
                        return value
                    }
                    streamIterator = iterator
                }
                return nil
            } else {
                guard !hasYielded, let fallbackSnapshot else { return nil }
                hasYielded = true
                return fallbackSnapshot
            }
        }

        public typealias Element = Snapshot
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(fallbackSnapshot: fallbackSnapshot, stream: streaming)
    }

    nonisolated public func collect() async throws -> sending LanguageModelSession.Response<Content> {
        if let streaming {
            var last: Snapshot?
            for try await snapshot in streaming {
                last = snapshot
            }
            if let last {
                // Attempt to materialize a concrete Content from the last snapshot
                let finalContent: Content
                if let concrete = last.content as? Content {
                    finalContent = concrete
                } else {
                    finalContent = try Content(last.rawContent)
                }
                return LanguageModelSession.Response(
                    content: finalContent,
                    rawContent: last.rawContent,
                    transcriptEntries: [],
                    metadata: nil
                )
            }
        }

        if let fallbackSnapshot {
            let finalContent: Content
            if let concrete = fallbackSnapshot.content as? Content {
                finalContent = concrete
            } else {
                finalContent = try Content(fallbackSnapshot.rawContent)
            }
            return LanguageModelSession.Response(
                content: finalContent,
                rawContent: fallbackSnapshot.rawContent,
                transcriptEntries: [],
                metadata: nil
            )
        }

        throw ResponseStreamError.noSnapshots
    }
}

private enum ResponseStreamError: Error {
    case noSnapshots
}

// MARK: -

private actor RespondingState {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func decrement() -> Int {
        count = max(0, count - 1)
        return count
    }
}
