import Foundation
import Testing

@testable import AnyLanguageModel

private let openaiAPIKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]

@Suite("Token Usage Tracking")
struct TokenUsageTests {
    @Test func tokenUsageAddition() {
        let usage1 = TokenUsage(
            promptTokens: 10,
            completionTokens: 20,
            totalTokens: 30,
            cachedTokens: 5
        )

        let usage2 = TokenUsage(
            promptTokens: 15,
            completionTokens: 25,
            totalTokens: 40,
            cachedTokens: 10
        )

        let combined = usage1 + usage2
        #expect(combined.promptTokens == 25)
        #expect(combined.completionTokens == 45)
        #expect(combined.totalTokens == 70)
        #expect(combined.cachedTokens == 15)
    }

    @Test func tokenUsagePlusEquals() {
        var usage1 = TokenUsage(
            promptTokens: 10,
            completionTokens: 20,
            totalTokens: 30
        )

        let usage2 = TokenUsage(
            promptTokens: 5,
            completionTokens: 10,
            totalTokens: 15
        )

        usage1 += usage2
        #expect(usage1.promptTokens == 15)
        #expect(usage1.completionTokens == 30)
        #expect(usage1.totalTokens == 45)
    }

    @Test func tokenUsageCodable() throws {
        let usage = TokenUsage(
            promptTokens: 100,
            completionTokens: 200,
            totalTokens: 300,
            cachedTokens: 50
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(usage)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TokenUsage.self, from: data)

        #expect(decoded == usage)
    }

    @Suite("OpenAI Token Usage", .enabled(if: openaiAPIKey?.isEmpty == false))
    struct OpenAITokenUsageTests {
        private let apiKey = openaiAPIKey!

        private var model: OpenAILanguageModel {
            OpenAILanguageModel(apiKey: apiKey, model: "gpt-4o-mini", apiVariant: .chatCompletions)
        }

        @Test func responseContainsUsage() async throws {
            let session = LanguageModelSession(model: model)

            let response = try await session.respond(to: "Say hello in 5 words")

            // OpenAI should provide token usage
            #expect(response.metadata?.tokenUsage != nil)

            if let usage = response.metadata?.tokenUsage {
                #expect(usage.promptTokens ?? 0 > 0)
                #expect(usage.completionTokens ?? 0 > 0)
                #expect(usage.totalTokens ?? 0 > 0)
            }
        }

        @Test func cumulativeUsageTracking() async throws {
            let session = LanguageModelSession(model: model)

            // First request
            let response1 = try await session.respond(to: "Count to 3")
            #expect(response1.metadata?.tokenUsage != nil)

            // Check cumulative usage after first request
            #expect(session.cumulativeUsage != nil)
            let firstUsage = session.cumulativeUsage!
            #expect(firstUsage.totalTokens ?? 0 > 0)

            // Second request
            let response2 = try await session.respond(to: "Count to 5")
            #expect(response2.metadata?.tokenUsage != nil)

            // Check cumulative usage after second request
            #expect(session.cumulativeUsage != nil)
            let secondUsage = session.cumulativeUsage!
            #expect(secondUsage.totalTokens ?? 0 > firstUsage.totalTokens ?? 0)

            // Cumulative should equal sum of individual responses
            if let usage1 = response1.metadata?.tokenUsage,
                let usage2 = response2.metadata?.tokenUsage
            {
                let expected = usage1 + usage2
                #expect(secondUsage.totalTokens == expected.totalTokens)
            }
        }

        @Test func responsesAPIUsage() async throws {
            let responsesModel = OpenAILanguageModel(
                apiKey: apiKey,
                model: "gpt-4o-mini",
                apiVariant: .responses
            )
            let session = LanguageModelSession(model: responsesModel)

            let response = try await session.respond(to: "Say hello briefly")

            // Responses API should also provide token usage
            #expect(response.metadata?.tokenUsage != nil)

            if let usage = response.metadata?.tokenUsage {
                #expect(usage.totalTokens ?? 0 > 0)
            }
        }
    }
}
