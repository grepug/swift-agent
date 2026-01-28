import Foundation

/// Silent observer that does nothing (default)
public struct SilentObserver: AgentCenterObserver {
    public init() {}

    public func observe(_ event: AgentCenterEvent) {
        // No-op
    }
}
