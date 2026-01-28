import AnyLanguageModel
import Foundation

extension FileDebugObserver {
    /// Sanitize agent ID for use in directory names: lowercase and replace whitespace with hyphens
    func sanitizeAgentId(_ agentId: String) -> String {
        return agentId.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Format timestamp as YYYYMMDDHHMMSS in local timezone
    func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Get first 6 characters of UUID string (lowercase)
    func uuidPrefix(_ uuid: UUID) -> String {
        return String(uuid.uuidString.lowercased().prefix(6))
    }

    func sanitizeFilenameComponent(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mappedCharacters: [Character] = input.unicodeScalars.map { scalar in
            if allowed.contains(scalar) {
                return Character(scalar)
            } else {
                return "_"
            }
        }
        var sanitized = String(mappedCharacters)
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        if sanitized.isEmpty {
            sanitized = "tool"
        }
        return sanitized
    }
}
