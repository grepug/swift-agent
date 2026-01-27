import Dependencies
import Foundation

// MARK: - Dependency Key

struct AgentObserversKey: DependencyKey {
    static let liveValue: [any AgentCenterObserver] = []
    static let testValue: [any AgentCenterObserver] = []
}

extension DependencyValues {
    public var agentObservers: [any AgentCenterObserver] {
        get { self[AgentObserversKey.self] }
        set { self[AgentObserversKey.self] = newValue }
    }
}
