# EPIC-RES-0 — Source-of-Truth Consolidation

> 🔴 **EXECUTOR MODEL — HIGHER MODEL / HUMAN. Do NOT run on 4.6.** Choosing the canonical
> copy and reconciling divergent mirrors is judgment; a wrong delete loses live code.
> (4.6 may do the mechanical move *after* the canonical set is named.)

**Layer:** Maintenance · **Status:** Not started
**Scheduling:** Runs **alone, first**. Hard gate for all other epics.
**Parallel with:** none · **Blocked by:** none

---

## Goal

Collapse the mirrored directory structure so there is exactly one canonical file per
artifact. Eliminate the risk that any later refactor edits a dead copy that never
deploys.

## Why (resilience rationale)

The repo ships duplicated definitions across mirrored folders. A schema or logic change
applied to the wrong copy silently does nothing in production — the most expensive class
of bug because it looks done. Every other epic in this PRD edits files that currently
have a twin, so this must land first.

## Known duplicate pairs

| Artifact | Pair A | Pair B |
|---|---|---|
| Tables | `table/` | `tables/` |
| APIs | `api/` | `apis/` |
| Functions | `function/` | `functions/` |
| Tools | `tools/` | `ai/tool/` |
| Workflow tests | `workflow_test/` | `workflow_tests/` |
| Webapp | `webapp/protype-1` | `webapp/protype-2` |

---

## Stories

### US-RES-0-01 — Diff the mirrored directories
**Change:** Produce a byte/content diff report for each duplicate pair; flag any files
that differ between copies.
**Acceptance:**
- A report lists, per pair: identical files, differing files, files unique to one side.
- No file is deleted in this story.

### US-RES-0-02 — Reconcile divergent copies
**Change:** For every differing file, decide and merge the correct canonical content.
**Acceptance:**
- Each divergence is resolved into one agreed version.
- Resolution rationale is recorded in the PR description.

### US-RES-0-03 — Choose canonical dirs and remove mirrors
**Change:** Pick one canonical directory per artifact type and delete the redundant
mirror. Update any path references / imports.
**Acceptance:**
- Only one directory remains per artifact type.
- Build, tests, and deploy config resolve with no broken paths.

### US-RES-0-04 — Quarantine scratch artifacts
**Change:** Move one-off scripts (`tmp/fix_*.py`) and loose root `*.txt` dumps out of the
tracked tree; add them to `.gitignore`.
**Acceptance:**
- `tmp/` and root scratch `.txt` files are gitignored.
- Repo root contains only intentional, documented files.

---

## Executor Contract (read before coding)

**Touchpoints (only):** the six duplicate pairs — `table/`↔`tables/`, `api/`↔`apis/`,
`function/`↔`functions/`, `tools/`↔`ai/tool/`, `workflow_test/`↔`workflow_tests/`,
`webapp/protype-1`↔`webapp/protype-2`. Plus `tmp/` and root `*.txt` for US-RES-0-04.

**Canonical rule:** keep the copy that contains a `guid =` line (live Xano-synced);
the copy without a guid is the stale mirror. Verified example: `table/account.xs` has
`guid = "937..."`, `tables/2_account.xs` does not — so `table/` wins for that file.

**Do NOT touch:** the *content* of any `.xs` file. This epic only **moves/deletes**
files. Zero logic edits in the same PR — that keeps the diff a pure pathing change.

**Verify with:**
- Hash-compare each surviving file against its deleted twin (or record the reconciled
  diff in US-RES-0-02).
- Repo-wide grep for the deleted directory name → zero references remain.
- CI/build green on the consolidated tree.

**Parity:** surviving file content is byte-identical to the canonical input (no edits).

**Stop-and-ask if:** the two copies of a file differ and it's not obvious which is live
(guid present on both, or neither) — do not pick blindly.

## Definition of Done

- One canonical source per artifact; mirrors deleted.
- CI green on the consolidated tree.
- A short note in the PR documents which directory won for each artifact type.
