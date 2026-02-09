import Testing
import Foundation
@testable import AnyLanguageModel

@Suite("Transcript Tool Call Storage and Reconstruction")
struct TranscriptToolCallTests {
    @Test("ToolCall has public initializer")
    func toolCallPublicInit() {
        let toolCall = Transcript.ToolCall(
            id: "call_123",
            toolName: "get_weather",
            arguments: GeneratedContent(properties: ["location": "San Francisco"])
        )
        
        #expect(toolCall.id == "call_123")
        #expect(toolCall.toolName == "get_weather")
    }
    
    @Test("ToolCalls has public initializer")
    func toolCallsPublicInit() {
        let call1 = Transcript.ToolCall(
            id: "call_1",
            toolName: "tool_a",
            arguments: GeneratedContent(properties: [:])
        )
        let call2 = Transcript.ToolCall(
            id: "call_2",
            toolName: "tool_b",
            arguments: GeneratedContent(properties: [:])
        )
        
        let toolCalls = Transcript.ToolCalls(id: "toolcalls_1", [call1, call2])
        
        #expect(toolCalls.id == "toolcalls_1")
        #expect(toolCalls.calls.count == 2)
        #expect(toolCalls.calls[0].id == "call_1")
        #expect(toolCalls.calls[1].id == "call_2")
    }
    
    @Test("ToolOutput has public initializer")
    func toolOutputPublicInit() {
        let output = Transcript.ToolOutput(
            id: "call_123",
            toolName: "get_weather",
            segments: [.text(.init(content: "72°F and sunny"))]
        )
        
        #expect(output.id == "call_123")
        #expect(output.toolName == "get_weather")
        #expect(output.segments.count == 1)
    }
    
    @Test("Segment.toolCalls case can store tool calls")
    func segmentToolCallsCase() {
        let toolCall = Transcript.ToolCall(
            id: "call_123",
            toolName: "calculate",
            arguments: GeneratedContent(properties: ["expression": "2+2"])
        )
        
        let toolCallsSegment = Transcript.ToolCallsSegment(
            id: "segment_1",
            calls: [toolCall]
        )
        
        let segment = Transcript.Segment.toolCalls(toolCallsSegment)
        
        #expect(segment.id == "segment_1")
        
        if case .toolCalls(let extractedSegment) = segment {
            #expect(extractedSegment.calls.count == 1)
            #expect(extractedSegment.calls[0].id == "call_123")
            #expect(extractedSegment.calls[0].toolName == "calculate")
        } else {
            Issue.record("Expected toolCalls segment case")
        }
    }
    
    @Test("Response can contain tool calls in segments")
    func responseWithToolCallsSegment() {
        let toolCall = Transcript.ToolCall(
            id: "call_abc",
            toolName: "search",
            arguments: GeneratedContent(properties: ["query": "weather"])
        )
        
        let response = Transcript.Response(
            id: "response_1",
            assetIDs: [],
            segments: [
                .text(.init(content: "I'll search for that...")),
                .toolCalls(.init(calls: [toolCall]))
            ]
        )
        
        #expect(response.segments.count == 2)
        
        if case .text(let textSegment) = response.segments[0] {
            #expect(textSegment.content == "I'll search for that...")
        } else {
            Issue.record("Expected text segment")
        }
        
        if case .toolCalls(let toolCallsSegment) = response.segments[1] {
            #expect(toolCallsSegment.calls.count == 1)
            #expect(toolCallsSegment.calls[0].toolName == "search")
        } else {
            Issue.record("Expected toolCalls segment")
        }
    }
    
    @Test("Entry.toolCalls stores tool calls at entry level")
    func entryToolCalls() {
        let call1 = Transcript.ToolCall(
            id: "call_1",
            toolName: "tool1",
            arguments: GeneratedContent(properties: [:])
        )
        let call2 = Transcript.ToolCall(
            id: "call_2",
            toolName: "tool2",
            arguments: GeneratedContent(properties: [:])
        )
        
        let entry = Transcript.Entry.toolCalls(
            Transcript.ToolCalls([call1, call2])
        )
        
        if case .toolCalls(let toolCalls) = entry {
            #expect(toolCalls.calls.count == 2)
            #expect(toolCalls.calls[0].toolName == "tool1")
            #expect(toolCalls.calls[1].toolName == "tool2")
        } else {
            Issue.record("Expected toolCalls entry")
        }
    }
    
    @Test("Entry.toolOutput stores tool results")
    func entryToolOutput() {
        let entry = Transcript.Entry.toolOutput(
            Transcript.ToolOutput(
                id: "call_123",
                toolName: "get_temperature",
                segments: [
                    .text(.init(content: "Temperature: 72°F")),
                    .structure(.init(
                        source: "sensor",
                        content: GeneratedContent(properties: [
                            "value": 72,
                            "unit": "fahrenheit"
                        ])
                    ))
                ]
            )
        )
        
        if case .toolOutput(let output) = entry {
            #expect(output.id == "call_123")
            #expect(output.toolName == "get_temperature")
            #expect(output.segments.count == 2)
        } else {
            Issue.record("Expected toolOutput entry")
        }
    }
    
    @Test("Full conversation with tool calls can be reconstructed")
    func reconstructConversationWithToolCalls() {
        // Create a transcript that represents a full tool use conversation
        let transcript = Transcript(entries: [
            // User prompt
            .prompt(Transcript.Prompt(
                segments: [.text(.init(content: "What's the weather in San Francisco?"))]
            )),
            
            // Assistant response with tool call
            .response(Transcript.Response(
                assetIDs: [],
                segments: [
                    .text(.init(content: "I'll check the weather for you.")),
                    .toolCalls(.init(calls: [
                        Transcript.ToolCall(
                            id: "call_weather",
                            toolName: "get_weather",
                            arguments: GeneratedContent(properties: [
                                "location": "San Francisco"
                            ])
                        )
                    ]))
                ]
            )),
            
            // Tool call entry (alternative representation at entry level)
            .toolCalls(Transcript.ToolCalls([
                Transcript.ToolCall(
                    id: "call_weather",
                    toolName: "get_weather",
                    arguments: GeneratedContent(properties: [
                        "location": "San Francisco"
                    ])
                )
            ])),
            
            // Tool output/result
            .toolOutput(Transcript.ToolOutput(
                id: "call_weather",
                toolName: "get_weather",
                segments: [.text(.init(content: "72°F and sunny"))]
            )),
            
            // Final assistant response
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(.init(content: "The weather in San Francisco is 72°F and sunny."))]
            ))
        ])
        
        #expect(transcript.count == 5)
        
        // Verify we can access and reconstruct each part
        if case .prompt(let prompt) = transcript[0] {
            #expect(prompt.segments.count == 1)
        } else {
            Issue.record("Expected prompt entry")
        }
        
        if case .response(let response) = transcript[1] {
            #expect(response.segments.count == 2)
            if case .toolCalls(let toolCallsSegment) = response.segments[1] {
                #expect(toolCallsSegment.calls.count == 1)
                #expect(toolCallsSegment.calls[0].toolName == "get_weather")
            }
        } else {
            Issue.record("Expected response entry")
        }
        
        if case .toolCalls(let toolCalls) = transcript[2] {
            #expect(toolCalls.calls.count == 1)
            #expect(toolCalls.calls[0].id == "call_weather")
        } else {
            Issue.record("Expected toolCalls entry")
        }
        
        if case .toolOutput(let output) = transcript[3] {
            #expect(output.toolName == "get_weather")
            #expect(output.segments.count == 1)
        } else {
            Issue.record("Expected toolOutput entry")
        }
        
        if case .response(let finalResponse) = transcript[4] {
            #expect(finalResponse.segments.count == 1)
        } else {
            Issue.record("Expected final response entry")
        }
    }
    
    @Test("ToolCallsSegment Codable roundtrip")
    func toolCallsSegmentCodable() throws {
        let original = Transcript.ToolCallsSegment(
            id: "seg_1",
            calls: [
                Transcript.ToolCall(
                    id: "call_1",
                    toolName: "test_tool",
                    arguments: GeneratedContent(properties: ["key": "value"])
                )
            ]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Transcript.ToolCallsSegment.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.calls.count == original.calls.count)
        #expect(decoded.calls[0].id == original.calls[0].id)
        #expect(decoded.calls[0].toolName == original.calls[0].toolName)
    }
    
    @Test("Segment.toolCalls Codable roundtrip")
    func segmentToolCallsCodable() throws {
        let original = Transcript.Segment.toolCalls(
            Transcript.ToolCallsSegment(
                calls: [
                    Transcript.ToolCall(
                        id: "call_1",
                        toolName: "test",
                        arguments: GeneratedContent(properties: [:])
                    )
                ]
            )
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Transcript.Segment.self, from: data)
        
        if case .toolCalls(let decodedSegment) = decoded {
            #expect(decodedSegment.calls.count == 1)
            #expect(decodedSegment.calls[0].toolName == "test")
        } else {
            Issue.record("Expected toolCalls segment after decoding")
        }
    }
}
