import Foundation

/// A type-erased codable value placeholder
/// In a real implementation, use a proper JSON type or SwiftUI's AnyCodable
public struct AnyCodable: Codable, Sendable {
    private let stringValue: String
    
    public init(_ value: String = "{}") {
        self.stringValue = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            stringValue = string
        } else {
            stringValue = "{}"
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}
