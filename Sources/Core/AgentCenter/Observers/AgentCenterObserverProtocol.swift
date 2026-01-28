import Foundation

/// Protocol for observing agent center events
public protocol AgentCenterObserver: Sendable {
    /// Called when an event occurs in the agent center
    func observe(_ event: AgentCenterEvent)
}
