import Foundation

/// Definition of a tool from an MCP server.
///
/// Contains the metadata needed to expose the tool to a language model,
/// including its name, description, and input schema.
struct MCPToolDefinition: Decodable, Sendable {
    let name: String
    let description: String?
    let inputSchema: JSONSchema

    /// JSON Schema for tool parameters
    struct JSONSchema: Decodable, Sendable {
        let type: String
        let properties: [String: Property]?
        let required: [String]?

        struct Property: Decodable, Sendable {
            let type: String?
            let description: String?
            let items: Items?
            let `enum`: [String]?

            struct Items: Decodable, Sendable {
                let type: String?
            }
        }
    }

    /// Converts JSON Schema to GenerationSchema for use with Tool protocol
    func toGenerationSchema() -> GenerationSchema {
        // Convert to DynamicGenerationSchema first
        let dynamicSchema = convertToDynamicSchema()

        // Convert to GenerationSchema
        do {
            return try GenerationSchema(root: dynamicSchema, dependencies: [])
        } catch {
            // Fallback to empty object schema if conversion fails
            let fallback = DynamicGenerationSchema(
                name: "Fallback",
                properties: []
            )
            // If even this fails, we have a serious problem, but this should never happen
            return try! GenerationSchema(root: fallback, dependencies: [])
        }
    }

    /// Converts to DynamicGenerationSchema
    private func convertToDynamicSchema() -> DynamicGenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = []

        // Convert each property
        for (name, property) in inputSchema.properties ?? [:] {
            let schema = convertPropertyToDynamicSchema(property)
            let isOptional = !(inputSchema.required ?? []).contains(name)

            properties.append(
                DynamicGenerationSchema.Property(
                    name: name,
                    description: property.description,
                    schema: schema,
                    isOptional: isOptional
                )
            )
        }

        return DynamicGenerationSchema(
            name: self.name,
            description: self.description,
            properties: properties
        )
    }

    /// Converts a JSON Schema property to a DynamicGenerationSchema.
    private func convertPropertyToDynamicSchema(_ property: JSONSchema.Property) -> DynamicGenerationSchema {
        guard let type = property.type else {
            return DynamicGenerationSchema(type: String.self)
        }

        switch type {
        case "string":
            return DynamicGenerationSchema(type: String.self)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        case "array":
            if let items = property.items {
                let itemSchema = convertItemsToDynamicSchema(items)
                return DynamicGenerationSchema(arrayOf: itemSchema)
            }
            return DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self))
        case "object":
            // For nested objects, create a simple schema
            return DynamicGenerationSchema(name: "NestedObject", properties: [])
        default:
            return DynamicGenerationSchema(type: String.self)
        }
    }

    /// Converts JSON Schema array items to a DynamicGenerationSchema.
    private func convertItemsToDynamicSchema(_ items: JSONSchema.Property.Items) -> DynamicGenerationSchema {
        let type = items.type ?? "string"

        switch type {
        case "string":
            return DynamicGenerationSchema(type: String.self)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        default:
            return DynamicGenerationSchema(type: String.self)
        }
    }
}
