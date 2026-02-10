# SwiftAgent Improvement Plan (Swifty + Comprehensive)

## Status Snapshot (2026-02-10)
- Phase 1: ✅ Completed
- Phase 2: ✅ Completed
- Phase 3: 🚧 In progress (streaming parity landed; execution policy + context-window strategy pending)
- Phase 4: ⏳ Planned

## Goal
Evolve SwiftAgent from a strong minimal core into a production-ready Swift library with safer runtime behavior, clearer API ergonomics, and complete agent-runtime capabilities.

## Constraints
- Keep current public API mostly source-compatible in Phase 1.
- Prefer incremental, test-backed changes.
- Preserve actor isolation and structured concurrency patterns.

## Phase 1: Runtime Hardening ✅ Completed
1. Replace crash paths (`fatalError`, force unwrap decoding) with typed errors.
2. Remove known concurrency warning in hook background cleanup.
3. Add regression tests for:
   - missing model error path in agent execution,
   - invalid UTF-8 decoding behavior for run content.

Success criteria:
- No forced crash path in core runtime flow.
- Current tests still pass.
- New tests lock in behavior.

Completion notes:
- Missing model path returns `AgentError.modelNotFound` (no crash path in core runtime flow).
- Invalid UTF-8 payload decoding in `Run` is guarded by throwing behavior.
- Regression tests added in `RuntimeHardeningTests` and passing.

## Phase 2: API Swifty-ness and ergonomics ✅ Completed
1. Refine public surface for `Agent` and related descriptors (reduce hidden package-only friction where needed).
2. Improve naming consistency and result-centric return types for command APIs.
3. Remove API/docs drift and publish canonical examples for SwiftPM consumers.

Success criteria:
- Docs compile against package as-written.
- Fewer required "inside-the-package" assumptions.

Completion notes:
- Convenience API ergonomics covered by dedicated tests (`APIErgonomicsTests`).
- Public-facing usage examples updated in README.

## Phase 3: Comprehensive runtime features 🚧 In Progress
1. True streaming API (token/delta events), not one-shot wrapped streaming.
2. Execution policy object (`timeout`, retries, cancellation propagation, max tool calls).
3. Context-window strategy (history trimming + summary compaction hooks).

Success criteria:
- Feature parity between run and stream paths.
- Predictable control over latency/cost/failure behavior.

Current state:
- Streaming path with token/delta handling and parity coverage is present (`StreamAgentParityTests`).
- Execution policy object is not yet introduced.
- Context-window trimming + summary compaction strategy is not yet implemented.

## Phase 4: Observability and storage maturity ⏳ Planned
1. Populate run metrics/tool execution records consistently.
2. Add storage backend options (SQLite adapter first).
3. Structured telemetry export hooks.

Success criteria:
- Runs are auditable and measurable by default.
- Storage is suitable for long-lived sessions.

## Immediate Next Step
Implement Phase 3 remaining items in `LiveAgentCenter`:
1. Introduce an execution policy object (`timeout`, retries, cancellation propagation, max tool calls).
2. Add context-window strategy hooks (history trimming + summary compaction).
3. Add tests that validate parity between `runAgent` and `streamAgent` under policy constraints.
