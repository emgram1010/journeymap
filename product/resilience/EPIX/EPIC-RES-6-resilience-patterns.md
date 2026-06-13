# EPIC-RES-6 — Resilience Patterns: Idempotency & Error Handling

> 🔴 **EXECUTOR MODEL — HIGHER MODEL. Do NOT run on 4.6.** Transaction/idempotency
> strategy is architectural and has no repo precedent. Design it on a higher model; 4.6
> may wire the standardized `failed[]` response shape afterward.

**Layer:** Logic · **Status:** Not started
**Scheduling:** **Parallel with** RES-4, RES-5, RES-3, RES-8 · **Blocked by** RES-0

---

## Goal

Make multi-write operations safe under partial failure and retries: a repeated or
interrupted call leaves the system in a correct, predictable state.

## Why (resilience rationale)

Batch tools (`fill_cells`, `batch_update`, `batch_set_status`, `scaffold_map`) write many
rows per call. Today a mid-batch failure can leave a partial write, and a client retry
can double-apply. At scale and under AI-driven concurrency, partial/duplicate writes
become a steady source of corruption. This epic adds transactional boundaries,
idempotency, and explicit partial-failure reporting.

---

## Stories

### US-RES-6-01 — Transactional batch writes
**Change:** Wrap multi-row writes (scaffold, batch cell writes) so they commit
all-or-nothing where the operation is logically atomic.
**Acceptance:**
- A forced mid-batch failure leaves no partial structural write.

### US-RES-6-02 — Idempotent retries
**Change:** Ensure re-submitting the same batch (same keys/content) does not create
duplicates or double-apply status changes.
**Acceptance:**
- Replaying an identical call is a no-op on already-applied items.

### US-RES-6-03 — Structured partial-failure response
**Change:** Standardize the applied/skipped/failed response shape across batch tools,
with a reason per failed item.
**Acceptance:**
- Every batch tool returns `applied[]`, `skipped[]`, `failed[]` with reasons.

### US-RES-6-04 — Guard rails on expensive ops
**Change:** Cap batch size inputs and reject oversized payloads early with a clear error
rather than timing out mid-write.
**Acceptance:**
- Oversized batches are rejected before any write, with an actionable message.

### US-RES-6-05 — Publish/compile resilience
**Change:** Ensure `publish_map` / snapshot compile is safe to retry and reports webhook
push failures without corrupting the snapshot version.
**Acceptance:**
- A failed webhook push does not roll back or duplicate the compiled snapshot.
- Version increments remain monotonic on retry.

---

## Executor Contract (read before coding)

**Touchpoints (only):** `tools/51_fill_cells.xs`, `tools/5_batch_update.xs`,
`tools/10_batch_set_status.xs`, `tools/56_scaffold_map.xs`, `tools/55_publish_map.xs`
(+ its mirror in `ai/tool/` per the canonical-guid rule).

**⚠ Top stop-and-ask (do FIRST):** Confirm whether Xano exposes a **transaction /
atomic-batch** primitive. There is no transaction example in this repo. Do **not** invent
one. If unavailable, the all-or-nothing requirement (US-RES-6-01) needs a design
decision (e.g. pre-validate-then-write, or compensating cleanup) — ask, don't guess.

**Do NOT touch:**
- The existing applied/skipped/locked/confirmed semantics — extend the response with a
  `failed[]` array additively; don't rename existing keys.
- `automation_snapshot.version` monotonicity — never reset or decrement it on retry.

**Verify with:**
- Simulated mid-batch failure → no partial structural write remains.
- Replay an identical batch → no duplicates, no double-applied status (idempotent).
- Oversized batch → rejected **before** any write, with a clear message.

**Parity:** successful single calls behave exactly as today; new behavior only appears on
failure/retry/oversize paths.

## Definition of Done

- Batch writes are atomic and idempotent.
- Uniform partial-failure reporting across tools.
- Retry-safety covered by tests simulating mid-batch failure.
