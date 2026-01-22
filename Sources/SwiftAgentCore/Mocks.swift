import Foundation

/// Mock model for testing the agent without a real LLM
public struct MockModel: ModelProtocol {
    private let responses: [String]
    private var currentIndex = 0
    
    public init(responses: [String]) {
        self.responses = responses
    }
    
    public func generate(messages: [Message]) async throws -> ModelResponse {
        // For demo: just return a simple text response
        let response = responses.isEmpty ? "Hello! I'm a mock model." : responses[0]
        return ModelResponse(content: response, finishReason: .stop)
    }
}

/// Mock tool for testing
public struct CalculatorTool: ToolProtocol {
    public let name = "calculator"
    public let description = "Performs basic arithmetic operations"
    public let parameters = AnyCodable("""
        {
            "type": "object",
            "properties": {
                "operation": {"type": "string", "enum": ["add", "subtract", "multiply", "divide"]},
                "a": {"type": "number"},
                "b": {"type": "number"}
            },
            "required": ["operation", "a", "b"]
        }
        """)
    
    public init() {}
    
    public func execute(arguments: String) async throws -> String {
        // Parse JSON and perform calculation
        // For simplicity, returning a mock result
        return "Result: 42"
    }
}
