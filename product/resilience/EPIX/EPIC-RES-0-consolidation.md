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

## Directory classification (verified against `.xano/config.json`)

The source of truth is `.xano/config.json` — its `paths` block lists the live Xano-synced
directories. Anything not listed there does not deploy.

| Artifact | ✅ Canonical (live) | ❌ Dead snapshot — DELETE | 🔁 Intentional mirror — KEEP |
|---|---|---|---|
| Tables | `tables/` | `table/` | — |
| APIs | `apis/` | `api/` | — |
| Functions | `functions/` | `function/` | — |
| Workflow tests | `workflow_tests/` | `workflow_test/` | — |
| Tools | `tools/` | — | `ai/tool/` (mirror per leakage epic) |
| MCP servers | `mcp_servers/` | — | `ai/mcp_server/` (mirror per leakage epic) |
| Webapp | TBD by user | — | `webapp/protype-1` vs `protype-2` — out of scope, owner decides |

The `guid =` line is **not** a canonical marker. It's an artifact of an older export
format and appears in the dead snapshots. Ignore it.

The fresh Xano pull (commit `11e4689`) confirmed the classification: Xano CLI itself
renamed `function/getting_started_template/role_based_access_control.xs` →
`functions/role_based_access_control.xs` (git rename R100). The three other singular
dirs (`table/`, `api/`, `workflow_test/`) follow the same pattern — Xano just hasn't
gotten to them yet.

---

## Stories

### US-RES-0-01 — Verify classification ✅ DONE (this PR)
**Change:** Confirm the dead/canonical/mirror classification against `.xano/config.json`
and the fresh Xano pull state.
**Acceptance:**
- Each of `table/`, `api/`, `function/`, `workflow_test/` has a name-for-name (or
  content-equivalent) counterpart in its canonical plural dir.
- Where content differs, the canonical dir has the **newer** leakage-math fields —
  confirming canonical is live (e.g. `apis/journey_map/63_...` has `cost_rate_value`,
  `cost_rate_unit` while `api/journey_map/journey_lens/actor_fields/...` does not).

### US-RES-0-02 — Delete dead singular directories
**Change:** `git rm -r` the four dead singular dirs.
**Acceptance:**
- `table/`, `api/`, `function/`, `workflow_test/` no longer exist in the tree.
- No code references them (grep returns zero hits in tracked source).
- `tools/`, `ai/tool/`, `mcp_servers/`, `ai/mcp_server/` are **untouched** — both halves
  of those intentional mirror pairs survive.

### US-RES-0-03 — Quarantine scratch artifacts
**Change:** Add `tmp/` and root scratch `*.txt` to `.gitignore`. Remove any tracked
scratch files from the index.
**Acceptance:**
- `tmp/` and root `*.txt` are gitignored.
- `git status` shows no scratch noise.

### US-RES-0-04 — Webapp prototype decision (DEFERRED)
**Change:** Decide whether `webapp/protype-1` and/or `protype-2` is canonical. **Out of
scope for this PR** — owner decides separately; not Xano-managed.

---

## Executor Contract (read before coding)

**Touchpoints (only):** the four dead singular dirs (`table/`, `api/`, `function/`,
`workflow_test/`), plus `.gitignore` and `tmp/`. Nothing else.

**Canonical rule:** `.xano/config.json` `paths` block is the source of truth. The `guid =`
heuristic is wrong — do not use it.

**Do NOT touch:**
- The *content* of any `.xs` file. This epic only deletes files; zero logic edits.
- `tools/`, `ai/tool/`, `mcp_servers/`, `ai/mcp_server/` — these are intentional mirrors
  (see EXECUTOR-PLAYBOOK Mirror-sync rule). Both halves stay live.
- `webapp/protype-1` and `webapp/protype-2` — deferred decision, not Xano-managed.

**Verify with:**
- `Test-Path table/, api/, function/, workflow_test/` → all return `False`.
- `git grep -l "^table/" -- . ; git grep -l "^api/" -- . ; ...` → zero hits in tracked
  source (path references in PRDs or docs are fine).
- `tools/`, `ai/tool/`, `mcp_servers/`, `ai/mcp_server/`, `tables/`, `apis/`,
  `functions/`, `workflow_tests/` all present, file counts unchanged.

**Stop-and-ask if:** a file in a "dead" dir contains content not present in the canonical
dir (would require a content-merge before delete — none expected after fresh Xano pull).

## Definition of Done

- The four dead singular dirs removed.
- `.gitignore` updated for scratch.
- Intentional mirrors (`tools/`↔`ai/tool/`, `mcp_servers/`↔`ai/mcp_server/`) preserved.
- Plural canonical dirs untouched, file counts unchanged.
- PR description notes the classification source (`.xano/config.json`) and the Xano
  rename evidence.
