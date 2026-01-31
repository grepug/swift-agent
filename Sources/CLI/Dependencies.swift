import Dependencies
import Foundation

extension DependencyValues {
    public var userId: UUID {
        get { self[UserIDKey.self] }
        set { self[UserIDKey.self] = newValue }
    }

    private enum UserIDKey: DependencyKey {
        static let liveValue: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        static let testValue: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
}
