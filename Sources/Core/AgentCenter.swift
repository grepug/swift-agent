import AnyLanguageModel
import Foundation

public class AgentCenter {
    var agents: [UUID: Agent]

    public init(agents: [Agent]) {
        self.agents = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
    }

    public func start() async throws {
        print("Starting Swift Agent Center with agents: \(agents.map { $0.value.name })")

        let tools = try await withThrowingTaskGroup { group in
            for (id, agent) in agents {
                for mcpConfig in agent.mcpServers {
                    group.addTask {
                        let server = try await MCPServerCenter.shared.server(for: mcpConfig)
                        let tools = try await server.discover()
                        print("Started MCP Server for agent \(agent.name): \(mcpConfig.name)")
                        return (id, tools)
                    }
                }
            }

            return try await group.reduce(into: [UUID: [any Tool]]()) { partialResult, pair in
                let (agentId, tools) = pair
                partialResult[agentId, default: []].append(contentsOf: tools)
            }
        }

        for (agentId, discoveredTools) in tools {
            if var agent = agents[agentId] {
                agent.tools.append(contentsOf: discoveredTools)
                agents[agentId] = agent
            }
        }
    }

    public func useAgent(id: UUID, sessionId: UUID, userId: UUID) async throws -> Agent {
        guard var agent = agents[id] else {
            fatalError("Agent with ID \(id) not found")
        }

        agent.sessionId = sessionId
        agent.userId = userId

        return agent
    }
}
