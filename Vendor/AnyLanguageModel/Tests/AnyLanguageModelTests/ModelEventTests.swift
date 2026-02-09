import Foundation
import Testing

@testable import AnyLanguageModel

@Suite("Model Events")
struct ModelEventTests {
    @Test func eventCreation() {
        let event = ModelEvent(
            modelIdentifier: "test-model",
            sessionID: UUID(),
            details: .requestStarted(
                ModelEvent.RequestStartedInfo(
                    promptText: "Test prompt",
                    options: GenerationOptions(),
                    transcriptEntries: [],
                    availableTools: []
                )
            )
        )

        #expect(event.modelIdentifier == "test-model")
        if case .requestStarted(let info) = event.details {
            #expect(info.promptText == "Test prompt")
            #expect(info.transcriptEntries.isEmpty)
            #expect(info.availableTools.isEmpty)
        } else {
            Issue.record("Expected requestStarted event")
        }
    }

    @Test func callbackEventHandler() async throws {
        let model = MockLanguageModel { _, _ in "Test response" }
        let session = LanguageModelSession(model: model)

        actor EventStore {
            var events: [ModelEvent] = []
            func append(_ event: ModelEvent) {
                events.append(event)
            }
            func getEvents() -> [ModelEvent] {
                return events
            }
        }

        let store = EventStore()

        session.onEvent = { event in
            Task { await store.append(event) }
        }

        _ = try await session.respond(to: "Test prompt")

        // Give events time to process
        try await Task.sleep(for: .milliseconds(50))

        let receivedEvents = await store.getEvents()

        // Should have request started and completed events
        #expect(receivedEvents.count >= 2)

        let hasStarted = receivedEvents.contains { event in
            if case .requestStarted = event.details { return true }
            return false
        }
        #expect(hasStarted)

        let hasCompleted = receivedEvents.contains { event in
            if case .requestCompleted = event.details { return true }
            return false
        }
        #expect(hasCompleted)
    }

    @Test func completedEventContainsTokenUsage() async throws {
        let model = MockLanguageModel { _, _ in "Response" }
        let session = LanguageModelSession(model: model)

        actor InfoHolder {
            var info: ModelEvent.RequestCompletedInfo?
            func set(_ newInfo: ModelEvent.RequestCompletedInfo) {
                info = newInfo
            }
            func get() -> ModelEvent.RequestCompletedInfo? {
                return info
            }
        }

        let holder = InfoHolder()

        session.onEvent = { event in
            Task {
                if case .requestCompleted(let info) = event.details {
                    await holder.set(info)
                }
            }
        }

        _ = try await session.respond(to: "Test")

        try await Task.sleep(for: .milliseconds(50))
        let completedInfo = await holder.get()

        #expect(completedInfo != nil)
        #expect(completedInfo?.content == "Response")
        #expect(completedInfo?.contentLength == 8)
        #expect(completedInfo?.duration ?? 0 >= 0)
        // MockLanguageModel doesn't provide token usage, but field should exist
        // Real models (like OpenAI) will populate this field
    }

    @Test func failedEventOnError() async throws {
        let model = MockLanguageModel { _, _ in
            throw NSError(domain: "test", code: 1)
        }
        let session = LanguageModelSession(model: model)

        actor InfoHolder {
            var info: ModelEvent.RequestFailedInfo?
            func set(_ newInfo: ModelEvent.RequestFailedInfo) {
                info = newInfo
            }
            func get() -> ModelEvent.RequestFailedInfo? {
                return info
            }
        }

        let holder = InfoHolder()

        session.onEvent = { event in
            Task {
                if case .requestFailed(let info) = event.details {
                    await holder.set(info)
                }
            }
        }

        do {
            _ = try await session.respond(to: "Test")
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }

        try await Task.sleep(for: .milliseconds(50))
        let failedInfo = await holder.get()

        #expect(failedInfo != nil)
        #expect(failedInfo?.duration ?? 0 >= 0)
        #expect(!failedInfo!.errorDescription.isEmpty)
    }

    @Test func eventSessionIDMatches() async throws {
        let model = MockLanguageModel { _, _ in "Response" }
        let session = LanguageModelSession(model: model)

        actor IDHolder {
            var sessionID: UUID?
            func set(_ id: UUID) {
                sessionID = id
            }
            func get() -> UUID? {
                return sessionID
            }
        }

        let holder = IDHolder()

        session.onEvent = { event in
            Task {
                await holder.set(event.sessionID)
            }
        }

        _ = try await session.respond(to: "Test")

        try await Task.sleep(for: .milliseconds(50))
        let eventSessionID = await holder.get()

        #expect(eventSessionID == session.sessionID)
    }

    @Test func toolCallEvents() async throws {
        let model = MockLanguageModel { prompt, _ in
            // Simple mock response - doesn't actually call tools
            return "It's sunny in San Francisco"
        }
        let weatherTool = WeatherTool()
        let session = LanguageModelSession(model: model, tools: [weatherTool])

        actor ToolEventCollector {
            var startedEvents: [ModelEvent.ToolCallStartedInfo] = []
            var completedEvents: [ModelEvent.ToolCallCompletedInfo] = []
            var failedEvents: [ModelEvent.ToolCallFailedInfo] = []

            func addStarted(_ info: ModelEvent.ToolCallStartedInfo) {
                startedEvents.append(info)
            }

            func addCompleted(_ info: ModelEvent.ToolCallCompletedInfo) {
                completedEvents.append(info)
            }

            func addFailed(_ info: ModelEvent.ToolCallFailedInfo) {
                failedEvents.append(info)
            }

            func getEvents() -> (
                started: [ModelEvent.ToolCallStartedInfo], completed: [ModelEvent.ToolCallCompletedInfo],
                failed: [ModelEvent.ToolCallFailedInfo]
            ) {
                return (startedEvents, completedEvents, failedEvents)
            }
        }

        let collector = ToolEventCollector()

        session.onEvent = { (event: ModelEvent) in
            Task {
                switch event.details {
                case .toolCallStarted(let info):
                    await collector.addStarted(info)
                case .toolCallCompleted(let info):
                    await collector.addCompleted(info)
                case .toolCallFailed(let info):
                    await collector.addFailed(info)
                default:
                    break
                }
            }
        }

        // Note: MockLanguageModel doesn't actually trigger tool calls internally
        // This test verifies the event infrastructure is in place
        // Real tool call events are tested in model-specific tests
        _ = try await session.respond(to: "What's the weather?")

        try await Task.sleep(for: .milliseconds(50))
        let events = await collector.getEvents()

        // MockLanguageModel doesn't actually call tools, so we expect no tool events
        // Real models with tool support will emit these events
        #expect(events.started.isEmpty)
        #expect(events.completed.isEmpty)
        #expect(events.failed.isEmpty)
    }

    @Test func requestStartedContainsTranscript() async throws {
        let model = MockLanguageModel { _, _ in "Response" }
        let session = LanguageModelSession(model: model)

        actor InfoHolder {
            var info: ModelEvent.RequestStartedInfo?
            func set(_ newInfo: ModelEvent.RequestStartedInfo) {
                info = newInfo
            }
            func get() -> ModelEvent.RequestStartedInfo? {
                return info
            }
        }

        let holder = InfoHolder()

        session.onEvent = { (event: ModelEvent) in
            Task {
                if case .requestStarted(let info) = event.details {
                    await holder.set(info)
                }
            }
        }

        _ = try await session.respond(to: "Test prompt")

        try await Task.sleep(for: .milliseconds(50))
        let startedInfo = await holder.get()

        #expect(startedInfo != nil)
        #expect(!startedInfo!.transcriptEntries.isEmpty, "Should have transcript entries including the prompt")
        #expect(startedInfo!.availableTools.isEmpty, "No tools in this session")
    }
}

private let openaiAPIKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]

@Suite("OpenAI Model Events", .enabled(if: openaiAPIKey?.isEmpty == false))
struct OpenAIModelEventTests {
    private let apiKey = openaiAPIKey!

    private var model: OpenAILanguageModel {
        OpenAILanguageModel(apiKey: apiKey, model: "gpt-4o-mini")
    }

    @Test func realAPIEventWithTokenUsage() async throws {
        let session = LanguageModelSession(model: model)

        actor InfoHolder {
            var info: ModelEvent.RequestCompletedInfo?
            func set(_ newInfo: ModelEvent.RequestCompletedInfo) {
                info = newInfo
            }
            func get() -> ModelEvent.RequestCompletedInfo? {
                return info
            }
        }

        let holder = InfoHolder()

        session.onEvent = { event in
            Task {
                if case .requestCompleted(let info) = event.details {
                    await holder.set(info)
                }
            }
        }

        _ = try await session.respond(to: "Say 'hello' in one word")

        try await Task.sleep(for: .milliseconds(50))
        let completedInfo = await holder.get()

        #expect(completedInfo != nil)
        #expect(!completedInfo!.content.isEmpty)

        // OpenAI should provide token usage
        #expect(completedInfo?.tokenUsage != nil)
        if let usage = completedInfo?.tokenUsage {
            #expect(usage.totalTokens ?? 0 > 0)
            #expect(usage.promptTokens ?? 0 > 0)
            #expect(usage.completionTokens ?? 0 > 0)
        }

        // Check duration is reasonable
        #expect(completedInfo!.duration > 0)
        #expect(completedInfo!.duration < 30)  // Should complete in under 30 seconds
    }

    @Test func streamingEventsWithChunks() async throws {
        let session = LanguageModelSession(model: model)

        actor StreamMetrics {
            var startedCount = 0
            var chunkCount = 0
            var completedInfo: ModelEvent.StreamingCompletedInfo?

            func incrementStarted() {
                startedCount += 1
            }

            func incrementChunk() {
                chunkCount += 1
            }

            func setCompleted(_ info: ModelEvent.StreamingCompletedInfo) {
                completedInfo = info
            }

            func getMetrics() -> (started: Int, chunks: Int, info: ModelEvent.StreamingCompletedInfo?) {
                return (startedCount, chunkCount, completedInfo)
            }
        }

        let metrics = StreamMetrics()

        session.onEvent = { event in
            Task {
                switch event.details {
                case .streamingStarted:
                    await metrics.incrementStarted()
                case .streamingChunk:
                    await metrics.incrementChunk()
                case .streamingCompleted(let info):
                    await metrics.setCompleted(info)
                default:
                    break
                }
            }
        }

        let stream = session.streamResponse(to: "Count from 1 to 5")
        for try await _ in stream {
            // Consume the stream
        }

        // Give events time to process
        try await Task.sleep(for: .milliseconds(100))

        let (started, chunks, completedInfo) = await metrics.getMetrics()

        #expect(started == 1)
        #expect(chunks > 0)  // Should have received chunks
        #expect(completedInfo != nil)
        #expect(completedInfo?.totalSize ?? 0 > 0)
        #expect(completedInfo?.chunkCount ?? 0 > 0)
    }

    @Test func multipleRequestsEventSequence() async throws {
        let session = LanguageModelSession(model: model)

        actor EventCollector {
            var eventSequence: [String] = []

            func append(_ value: String) {
                eventSequence.append(value)
            }

            func getSequence() -> [String] {
                return eventSequence
            }
        }

        let collector = EventCollector()

        session.onEvent = { event in
            Task {
                switch event.details {
                case .requestStarted:
                    await collector.append("started")
                case .requestCompleted:
                    await collector.append("completed")
                default:
                    break
                }
            }
        }

        _ = try await session.respond(to: "Say 'one'")
        _ = try await session.respond(to: "Say 'two'")

        // Give events time to process
        try await Task.sleep(for: .milliseconds(100))

        let sequence = await collector.getSequence()
        // With MockLanguageModel (no tools), expect exactly 2 started and 2 completed events
        // Note: Real models with tools may emit additional events for tool-calling API requests
        #expect(sequence == ["started", "completed", "started", "completed"])
    }

    @Test func toolCallEventsWithRealAPI() async throws {
        let weatherTool = WeatherTool()
        let session = LanguageModelSession(model: model, tools: [weatherTool])

        actor ToolEventCollector {
            var startedEvents: [ModelEvent.ToolCallStartedInfo] = []
            var completedEvents: [ModelEvent.ToolCallCompletedInfo] = []
            var failedEvents: [ModelEvent.ToolCallFailedInfo] = []

            func addStarted(_ info: ModelEvent.ToolCallStartedInfo) {
                startedEvents.append(info)
            }

            func addCompleted(_ info: ModelEvent.ToolCallCompletedInfo) {
                completedEvents.append(info)
            }

            func addFailed(_ info: ModelEvent.ToolCallFailedInfo) {
                failedEvents.append(info)
            }

            func getEvents() -> (
                started: [ModelEvent.ToolCallStartedInfo], completed: [ModelEvent.ToolCallCompletedInfo],
                failed: [ModelEvent.ToolCallFailedInfo]
            ) {
                return (startedEvents, completedEvents, failedEvents)
            }
        }

        let collector = ToolEventCollector()

        session.onEvent = { event in
            Task {
                switch event.details {
                case .toolCallStarted(let info):
                    await collector.addStarted(info)
                case .toolCallCompleted(let info):
                    await collector.addCompleted(info)
                case .toolCallFailed(let info):
                    await collector.addFailed(info)
                default:
                    break
                }
            }
        }

        _ = try await session.respond(to: "What's the weather in San Francisco?")

        // Give events time to process
        try await Task.sleep(for: .milliseconds(100))

        let events = await collector.getEvents()

        // Should have tool events since OpenAI will call the weather tool
        #expect(!events.started.isEmpty, "Expected at least one tool call started event")
        #expect(!events.completed.isEmpty, "Expected at least one tool call completed event")
        #expect(events.failed.isEmpty, "Expected no tool call failures")

        // Verify tool call details
        if let started = events.started.first {
            #expect(started.toolName == "getWeather")
            #expect(!started.arguments.isEmpty)
            #expect(started.callIndex == 0)
        }

        if let completed = events.completed.first {
            #expect(completed.toolName == "getWeather")
            #expect(completed.duration >= 0)
            #expect(!completed.result.isEmpty)
            #expect(completed.callIndex == 0)
        }
    }

    @Test func requestEventsHaveMatchingIDs() async throws {
        let model = MockLanguageModel { _, _ in "Test response" }
        let session = LanguageModelSession(model: model)

        actor EventCollector {
            var events: [ModelEvent] = []

            func append(_ event: ModelEvent) {
                events.append(event)
            }

            func getEvents() -> [ModelEvent] {
                return events
            }
        }

        let collector = EventCollector()
        session.onEvent = { event in
            Task { await collector.append(event) }
        }

        _ = try await session.respond(to: "Test")

        // Give events time to process
        try await Task.sleep(for: .milliseconds(50))

        let events = await collector.getEvents()

        // Find requestStarted and requestCompleted events
        let requestStarted = events.first { event in
            if case .requestStarted = event.details { return true }
            return false
        }

        let requestCompleted = events.first { event in
            if case .requestCompleted = event.details { return true }
            return false
        }

        #expect(requestStarted != nil, "Should have a requestStarted event")
        #expect(requestCompleted != nil, "Should have a requestCompleted event")

        // Verify they have the same event ID
        if let started = requestStarted, let completed = requestCompleted {
            #expect(
                started.id == completed.id,
                "requestStarted and requestCompleted events must share the same ID for correlation"
            )
        }
    }

    @Test func multipleAPICallsHaveCompleteTranscript() async throws {
        let model = MockLanguageModel { prompt, _ in
            // Simulate tool call on first request, then return result
            if prompt.description.contains("calculate") {
                return "I need to use the calculator tool"
            }
            return "The result is 42"
        }

        let session = LanguageModelSession(
            model: model,
            instructions: "You are a helpful assistant"
        )

        actor EventCollector {
            var events: [ModelEvent] = []

            func append(_ event: ModelEvent) {
                events.append(event)
            }

            func getEvents() -> [ModelEvent] {
                return events
            }
        }

        let collector = EventCollector()
        session.onEvent = { event in
            Task { await collector.append(event) }
        }

        // Make multiple requests to accumulate transcript
        _ = try await session.respond(to: "Please calculate something")
        _ = try await session.respond(to: "What was the result?")

        // Give events time to process
        try await Task.sleep(for: .milliseconds(50))

        let events = await collector.getEvents()

        // Get all requestStarted events
        let requestStartedEvents = events.compactMap { event -> ModelEvent.RequestStartedInfo? in
            if case .requestStarted(let info) = event.details {
                return info
            }
            return nil
        }

        #expect(requestStartedEvents.count >= 2, "Should have at least 2 requestStarted events")

        // First request should have initial transcript (instructions + prompt)
        if let firstRequest = requestStartedEvents.first {
            // Should have at least instructions
            #expect(firstRequest.transcriptEntries.count >= 1, "First request should have instructions in transcript")
        }

        // Second request should have accumulated transcript (instructions + prompt + response + new prompt)
        if requestStartedEvents.count >= 2 {
            let secondRequest = requestStartedEvents[1]
            // Should have grown from first request (instructions + first prompt + first response + second prompt)
            #expect(
                secondRequest.transcriptEntries.count >= 3,
                "Second request should have accumulated transcript entries"
            )
        }
    }
}
