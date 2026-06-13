# Executor Playbook — Building the Resilience Epics with Sonnet 4.6

> Read this **before** starting any RES-* story. It exists to stop drift, hallucinated
> Xano DSL, and silent scope creep on a cost-efficient model. The PRD's *Ground Rules*
> and *Snag Protocol* are binding; this file makes them operational.

---

## How to start any story (copy-paste prompt template)

```
Story: <US-RES-X-NN>
1. Read the epic file product/resilience/EPIX/EPIC-RES-X-*.md — the whole "Executor
   Contract" block.
2. Read every file listed under Touchpoints, in full, before proposing a diff.
3. Restate back to me: the exact files you will change, the exact change, and the
   "Verify with" check. Wait for my "go".
4. Make the smallest diff that passes "Verify with". Nothing else.
5. Run "Verify with". Paste the result. If it fails, fix and re-run — do not move on.
If anything is unclear or a needed Xano syntax is not already in this repo: STOP and ask.
```

Do not let the model skip step 3. The restate-before-coding step is the single biggest
drift preventer for 4.6.

---

## Canonical-file rule (most important anti-drift anchor)

This repo has mirrored directories. The **live, deployable** copy is the one that
contains a `guid =` line. The mirror without a guid is a stale export.

- Edit only the `guid`-bearing copy.
- If both copies still exist for the file you're touching, **RES-0 is not finished** —
  stop and flag it. Do not pick one yourself mid-feature.

| Likely canonical (has guid) | Likely stale mirror |
|---|---|
| `table/` | `tables/` |
| `api/` | `apis/` |
| `function/` | `functions/` |
| `tools/` / `ai/tool/` | resolve in RES-0 — confirm by guid |

---

## Xano DSL — never invent it

`.xs` is not SQL and not generic. Rules:

- To write a `db.query`, `where`, `sort`, `precondition`, `foreach`, `conditional`,
  index block, or filter — **copy the pattern from an existing file** and adapt values.
- Good reference files to copy from:
  - Query + in-memory lookup done right: `tools/2_get_map_state.xs`
  - Scoped query with `$auth`: `api/journey_map/journey_map/search_GET.xs`
  - Index block syntax: `table/journey_cell.xs`, `table/journey_map.xs`
- If an operation (e.g. transactions, partitioning, batch upsert) has **no example in
  the repo**, it may not be supported. **Stop and ask** — do not emit Postgres DDL or a
  made-up filter to make it "work".

---

## Parity discipline (for refactors — RES-5 especially)

A refactor that changes *how* but not *what* must prove it changed nothing observable.

- Before refactoring, capture the current output on a fixture (real map id) → save as
  the golden file.
- After refactoring, output must **byte-match** the golden file.
- `calculate_leakage` math is the canonical parity spec — see RES-5's Executor
  Contract for the exact unit/cost formulas. Do not "simplify" or "correct" the math.

---

## Definition of "done" per story

A story is done only when **all** are true:
1. The `Verify with` command/test passes (pasted as proof).
2. The diff touches only files in `Touchpoints`.
3. Nothing in `Do NOT touch` was modified.
4. For refactors: parity proven against the fixture.
5. One story, one PR.

If you cannot satisfy all five, the story is **blocked** — report why, don't force it.

---

## Stop-and-ask triggers (do not guess on these)

- Xano native **partitioning** support (RES-3).
- Xano **transaction / atomic batch** primitive (RES-6).
- Where `intent` is stored on `journey_map` — referenced in `list_maps` but absent from
  `table/journey_map.xs` schema (RES-4).
- The **telemetry sink** for metrics (RES-8).
- Any case where two non-identical mirror copies of a file still exist (RES-0).

---

## Model-split recommendation

Use the expensive model (or a human) to author each story's **plan + Verify-with test**
first. Then 4.6 executes "make this exact test pass against these exact files." 4.6 is
reliable at bounded execution and unreliable at open-ended design — these contracts
convert every story into the former.

---

## Per-epic model routing (read this before assigning work)

The deciding question is **"is the answer already in the repo?"** If a story is bounded —
clear touchpoints, a parity fixture or test as the gate, and syntax that exists somewhere
in the codebase to copy — 4.6 is reliable. If a story requires an **open design decision
or a platform capability the repo doesn't demonstrate**, route it up.

| Epic | Run on | Why |
|---|---|---|
| **RES-0** Consolidation | ⚠️ **Higher model** (or human) | Looks trivial, isn't. Deciding which mirror is canonical and reconciling divergent copies is judgment, and a wrong delete loses live code. Let a higher model do the diff/decision; 4.6 can do the mechanical move once the canonical set is named. |
| **RES-1** Data Integrity | 🟡 **4.6 with guardrails** | Constraint syntax is copyable. **But** the dedupe/backfill (US-RES-1-01/02) touches `confirmed`/`locked` data — review that PR closely. The constraint story itself (03) is safe for 4.6. |
| **RES-2** Indexing | ✅ **4.6** | Fully bounded: edit `index` blocks, verify with EXPLAIN. Syntax exists in the table files to copy. Lowest risk in the whole PRD. |
| **RES-3** Table Lifecycle | 🔴 **Higher model** | Hinges on whether Xano supports native partitioning/scheduled jobs — no repo example. High hallucination risk (4.6 will reach for Postgres DDL). Design the approach up top; 4.6 may implement once the mechanism is chosen. |
| **RES-4** Filtering & Pagination | 🟡 **4.6 with guardrails** | The `where`/pagination/scoping pattern is copyable from `search_GET.xs`. **But** the `intent`-field mystery and the pagination contract are design calls — resolve those (stop-and-ask) with a higher model, then 4.6 implements. |
| **RES-5** De-nesting | ✅ **4.6** (with the fixture) | Ideal 4.6 work: a golden-fixture test is the gate and `get_map_state.xs` is the pattern to copy. Provide the parity fixture **first**; then it's pure bounded execution. |
| **RES-6** Resilience Patterns | 🔴 **Higher model** | Transaction/idempotency design with no repo precedent. Atomicity strategy is architectural. Let a higher model design it; 4.6 can wire the standardized `failed[]` response shape. |
| **RES-7** Frontend Scale | 🟡 **4.6 with guardrails** | Virtualization is well-trodden ground 4.6 knows. **But** it must consume RES-4's exact contract and not touch APIs — scope-creep risk. Fine for 4.6 if RES-4 shipped first and the contract is pinned. |
| **RES-8** Observability | 🟡 **4.6 with guardrails** | Instrumentation is mechanical once the **sink is chosen** (stop-and-ask). Pick the sink with a higher model; 4.6 adds the emit calls. |

### Summary

- **Green — hand to 4.6 directly:** RES-2, RES-5 (give it the fixture first).
- **Yellow — 4.6 executes, but a higher model resolves the open decision first:**
  RES-1, RES-4, RES-7, RES-8.
- **Red — start on a higher model:** RES-0, RES-3, RES-6.

### Rule of thumb for any new story

> If the `Executor Contract` contains a **stop-and-ask** trigger, the *design* of that
> story belongs on a higher model. Once the decision is made and written down, the
> *implementation* can drop back to 4.6.
