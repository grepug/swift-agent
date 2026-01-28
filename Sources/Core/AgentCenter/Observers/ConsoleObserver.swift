import AnyLanguageModel
import Foundation

/// Console observer that prints events to stdout
public struct ConsoleObserver: AgentCenterObserver {
    private let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    public func observe(_ event: AgentCenterEvent) {
        let timestamp = ISO8601DateFormatter().string(from: event.timestamp)
        print("[\(timestamp)] \(event.description)")

        if verbose {
            printVerboseDetails(for: event)
        }
    }

    private func printVerboseDetails(for event: AgentCenterEvent) {
        switch event {
        case .modelRequestSending(_, let transcript, let message, _, _, _, _):
            print("  Message: \(message)")
            print("  Transcript entries: \(transcript.count)")
        case .modelResponseReceived(_, let content, _, _, let duration, let inTokens, let outTokens, _):
            print("  Response: \(content)")
            print("  Duration: \(String(format: "%.3f", duration))s")
            if let inTokens = inTokens {
                print("  Input tokens: \(inTokens)")
            }
            if let outTokens = outTokens {
                print("  Output tokens: \(outTokens)")
            }
        case .transcriptBuilt(let transcript, _, _, _):
            print("  Transcript entries: \(transcript.count)")
        case .toolExecutionStarted(let tool, let args, _, _):
            print("  Tool: \(tool)")
            print("  Arguments: \(args.prefix(100))\(args.count > 100 ? "..." : "")")
        case .toolExecutionCompleted(_, let tool, let result, let duration, let success, _):
            print("  Tool: \(tool)")
            print("  Duration: \(String(format: "%.3f", duration))s")
            print("  Success: \(success)")
            print("  Result: \(result.prefix(100))\(result.count > 100 ? "..." : "")")
        default:
            break
        }
    }
}
