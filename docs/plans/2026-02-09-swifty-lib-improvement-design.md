# SwiftAgent Improvement Plan (Swifty + Comprehensive)

## Goal
Evolve SwiftAgent from a strong minimal core into a production-ready Swift library with safer runtime behavior, clearer API ergonomics, and complete agent-runtime capabilities.

## Constraints
- Keep current public API mostly source-compatible in Phase 1.
- Prefer incremental, test-backed changes.
- Preserve actor isolation and structured concurrency patterns.

## Phase 1: Runtime Hardening (start now)
1. Replace crash paths (`fatalError`, force unwrap decoding) with typed errors.
2. Remove known concurrency warning in hook background cleanup.
3. Add regression tests for:
   - missing model error path in agent execution,
   - invalid UTF-8 decoding behavior for run content.

Success criteria:
- No forced crash path in core runtime flow.
- Current tests still pass.
- New tests lock in behavior.

## Phase 2: API Swifty-ness and ergonomics
1. Refine public surface for `Agent` and related descriptors (reduce hidden package-only friction where needed).
2. Improve naming consistency and result-centric return types for command APIs.
3. Remove API/docs drift and publish canonical examples for SwiftPM consumers.

Success criteria:
- Docs compile against package as-written.
- Fewer required "inside-the-package" assumptions.

## Phase 3: Comprehensive runtime features
1. True streaming API (token/delta events), not one-shot wrapped streaming.
2. Execution policy object (`timeout`, retries, cancellation propagation, max tool calls).
3. Context-window strategy (history trimming + summary compaction hooks).

Success criteria:
- Feature parity between run and stream paths.
- Predictable control over latency/cost/failure behavior.

## Phase 4: Observability and storage maturity
1. Populate run metrics/tool execution records consistently.
2. Add storage backend options (SQLite adapter first).
3. Structured telemetry export hooks.

Success criteria:
- Runs are auditable and measurable by default.
- Storage is suitable for long-lived sessions.

## Immediate Next Step
Implement Phase 1 in `LiveAgentCenter` and `Run` with new tests in `SwiftAgentCoreTests`.

## Update (2026-02-09)
- Phase 1 and Phase 2 were merged.
- Phase 3 started with `AgentRunOptions`:
  - per-run `GenerationOptions`,
  - tool allowlist/blocklist controls,
  - run/stream API parity for these controls,
  - validation for unknown allowed tools.
