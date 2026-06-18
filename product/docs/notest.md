Moved / formalized.

See `product/docs/DEPENDENCY-MAP.md` for the canonical dependency plan.

Legacy notes preserved below:

Sequential (must wait):

P0-1 → P0-2 — hard dependency. The violation log writes a record tagged with severity. If the severity schema doesn't exist yet, there's nothing to write against.
P0-1 + P0-2 → P1-1 — Dispatch reads both. It runs constraint checks (needs P0-1) and produces a violations report (needs P0-2).
Parallel (can run simultaneously):

P0-3 can run in parallel with P0-1 and P0-2. The execution status enum (on_time | late | missed | blocked) reads planned_duration vs actual_duration — it doesn't touch constraints at all. Completely independent work.
P1-2 can run in parallel with P1-1. Completion evidence (form | signature) only touches the goal_met check — no dependency on dispatch or constraint enforcement.

Sprint 1 (parallel tracks):
  Track A → P0-1 Constraint Engine
  Track B → P0-3 Execution Status Enum   ← independent, start now

Sprint 2:
  Track A → P0-2 Violation Log           ← unblocked once P0-1 ships

Sprint 3 (parallel tracks):
  Track A → P1-1 Dispatch Layer          ← needs P0-1 + P0-2
  Track B → P1-2 Completion Evidence     ← fully independent, start anytime