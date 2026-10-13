# Learning & Fixes Log

Findings and issues discovered while building phase-4 (OBS-1, GOV-1), kept
here so they get fixed on purpose instead of forgotten. Durable
platform-level constraints (how XanoScript actually behaves) live in
`CLAUDE.md` under "XanoScript constraints — verified live" — this file is
for **data problems, design deviations, and deferred work**, not syntax
rules.

Status key: 🔴 needs a human decision/action · 🟡 tracked, fix lands with a
later epic · ✅ fixed already.

---

## 🔴 Needs your action: validators destroyed, must be restored manually

**What happened:** Pushing OBS-1's new columns via `updateTableSchema`
silently dropped the `validators` on every OTHER field in the same table,
even though they were submitted back unchanged. Confirmed deterministic
(tried twice). A bug report is queued in `/feedback`.

**What was lost, and needs restoring in the Xano dashboard UI directly**
(not via this MCP tooling — that's the same broken path):

| Table | Field | Validator lost |
|---|---|---|
| `user` | `name` | trim |
| `user` | `email` | trim, lowercase |
| `user` | `password` | min length 8, at least 1 letter, at least 1 digit |
| `event_log` | `action` | trim |

**Impact while unfixed:** new signups could use a weak password; emails
aren't normalized (case/whitespace), which risks duplicate-looking
accounts or login lookups failing to match.

**Workaround going forward:** never run `updateTableSchema` against a
table that has validators. Add new data in a new table instead (this is
why `account_feature_flag` is its own table, not a JSON column on
`account`), or make the UI edit by hand.

---

## 🔴 Needs a decision: phase-3's table numbering collides with live data

Phase-3's `EPIC-PLN-1` reserved table ids **74–79** for the planner
tables (`planner_settings`, `planner_model`, `planner_workspace`,
`planner_agent`, `planner_timeline`, `planner_task`). When OBS-1 pushed to
the live workspace, ids **74–78 were already in use** by an unrelated,
already-deployed initiative:

| id | Live table | Belongs to |
|---|---|---|
| 74 | `execution_transaction` | leakage/execution tracking (not ours) |
| 75 | `journey_metric` | same |
| 76 | `transaction_line` | same |
| 77 | `stage_field_config` | same |
| 78 | `stage_event_log` | same |

**Fix:** before building phase-3, renumber its planned tables (Xano
assigns real ids on creation anyway — the epic's "74–79" was just a
planning placeholder). Update `EPIC-PLN-1-data-foundation.md` and
`product/stories/phase-3/README.md`'s ER diagram to not claim specific
ids. No schema work needed, just a doc correction before phase-3 starts.

---

## 🔴 Needs a decision: 729 orphaned rows already exist in production

GOV-1's first integrity-audit run (2026-10-13), over 1,231 cells / 139
stages / 163 lenses:

| Check | Count | Meaning |
|---|---|---|
| `journey_cell.journey_map` | 577 | cells pointing at a deleted map |
| `journey_lens.journey_map` | 76 | lenses pointing at a deleted map |
| `journey_stage.journey_map` | 52 | stages pointing at a deleted map |
| `journey_stage.primary_actor_lens` | 24 | owner key matches no lens in its map |
| `journey_cell.stage` / `journey_cell.lens` | 0 | clean |

**Root cause:** deleting a `journey_map` does not cascade-delete or
block-delete its stages/lenses/cells. The delete path has no guard.

**Not urgent today** — nothing reads orphaned rows, so they're inert.
**Becomes urgent once anything starts scanning `journey_cell`/`journey_stage`/`journey_lens` broadly** (e.g. a future admin report, a bulk
export, or ROLE-1/STAGE-1's backfill scripts), since those orphans will
show up as noise or errors.

**Fix, two parts:**
1. **Decide and implement delete behaviour for `journey_map`** (restrict
   vs. cascade vs. archive — GOV-1's delete matrix currently says
   "restrict if any version exists; archive the map instead," but that's
   for the *future* `journey_map_version` world. Today's actual delete
   path needs its own decision).
2. **Clean up the 729 existing orphans** — either a one-time delete script
   or an archive/backfill, once the delete-behaviour decision is made.
   Don't silently delete without checking whether any of these 577+76+52
   rows are something a user would notice disappearing.

Tracked as US-GOV-1-10 ("existing delete paths go through the guards"),
currently deferred because it needs `journey_map_version` (PUB-1) and
`owner_lens_id` (STAGE-1) first.

---

## 🟡 Fix lands with STAGE-1: the fragile `primary_actor_lens` text key

`journey_stage.primary_actor_lens` is a free-text key matched against
`journey_lens.key` within the same map. It's already wrong in 24 live
rows (see above). STAGE-1 replaces it with a real `owner_lens_id`
reference, which the schema audit and integrity audit will then enforce
properly. Until then, the integrity audit's check for this is the only
guard.

---

## 🟡 Workaround adopted, not fully resolved: `accessdenied` strips the message

Confirmed (GOV-1, via `runWorkspaceFunction`): `precondition { error_type
= "accessdenied" ... }` strips the custom message and returns a generic
"Access Denied". `error_type = "inputerror"` preserves it. **Decision:
use `inputerror` for every guard and VAL-1 rejection where the message
matters** (`assert_owns`, `assert_same_account`, `assert_state`,
`assert_not_archived`, `assert_fresh`, `require_platform_admin`,
`validate_field`-driven rejections) — all already built this way, with
the catalog code embedded in parens at the end of the message
(`"...( E-GOV-001)"`), consistent with how `xano.ts`'s `XanoHttpError`
already carries the correlation id as `.reference`.

**Still not confirmed:** whether `accessdenied` behaves the same way
through a REAL authenticated HTTP call (only tested via
`runWorkspaceFunction`, which has no `$auth` context and no real HTTP
layer). Low priority now that nothing relies on `accessdenied`
preserving a message — but worth a real check once a logged-in UI flow
actually calls one of these guards end to end (APP-1 is the first
candidate: a performer hitting a task that isn't theirs).

---

## 🟡 Needs a real HTTP test: `ops/feature_flag` is built but unverified end to end

Every piece it's built from is independently proven (`validate_field`
8/8 cases confirmed live, `require_platform_admin`, the db operations
from GOV-1), and it pushed with no parse error — but there's no tool in
this session that can make an authenticated HTTP call, and making an
account platform-admin to work around that is a decision for you, not
something to do unilaterally. **Needs a real test** (browser or curl
with a real admin session) once one exists: set a flag, confirm it
upserts (not duplicates) on a second call with the same account+key,
confirm each rejection path (bad flag_key, bad note, unknown account).

---

## 🟡 Needs a real HTTP test: TIME-1's cell PATCH validation is unverified end to end

Same gap as `ops/feature_flag` above. The four new preconditions on
`apis/journey_map/44_journey_cell_update_journey_cell_id_PATCH.xs`
(US-TIME-1-04 — duration/planned/actual ≥ 0, value-without-unit
rejected) pushed with no parse error, and the `$raw_input|has:"..."`
filter they rely on is a simple, documented object-key check, but
none of it has been exercised against a real request. **Needs a real
test** once an authenticated-HTTP tool exists: PATCH a real
`journey_cell` with a negative duration (expect rejection, nothing
written), a value with no unit (expect rejection), and a valid
value+unit (expect it persists and the existing leakage calc for a
test map is unaffected).

---

## 🟡 Needs a real HTTP/tool-call test: STAGE-1's owner endpoints are unverified end to end

Same gap as above, now on three call paths:

- `apis/journey_map/211_journey_stage_update_journey_stage_id_PATCH.xs` — owner_lens_id validation (same-map check, sync to `primary_actor_lens`, clear behaviour).
- `apis/journey_map/517_journey_lens_planned_work_journey_lens_id_PATCH.xs` — set/clear the planned-work switch.
- `ai/tool/update_stage_contract.xs` (70) — owner sync when the AI sets/clears `primary_actor_lens`.

All three are built entirely from pieces that WERE independently live-tested
against real/scratch data (`resolve_stage_owner`, `set_stage_owner`,
`does_planned_work`, `set_lens_planned_work`, and the `$raw_input` 3-way
omitted/null/value detection each relies on). Only each endpoint's own
request-to-response assembly is unverified. **Needs a real test** once an
authenticated-HTTP tool exists: PATCH a stage's owner from a different map
(expect rejection), a valid owner (expect `journey_stage_owner` row +
`primary_actor_lens` to agree), clear it (expect the row deleted); same
shape for the lens planned-work endpoint; and one `update_stage_contract`
tool call setting `primary_actor_lens` with a real session.

---

## 🟡 Deferred: the "does this row do planned work?" switch has no UI yet

The backend (US-STAGE-1-06) is complete and live-verified: table
`journey_lens_planned_work`, read function `does_planned_work.xs`, write
endpoint `517_journey_lens_planned_work_journey_lens_id_PATCH.xs`. What's
missing is the actual toggle control in the lens row header in `App.tsx`.
Not built because this session has no dev server running and no browser
tool invoked — adding new JSX to a large, canvas-heavy file and trusting it
without seeing it render would violate this project's own rule (CLAUDE.md:
start the dev server and check UI changes in a browser). **Needs:** start
`npm run dev`, add a small switch to the row header (reading its current
value via a `get_map`-style read or a dedicated GET, writing via 517),
confirm required-field tags appear/disappear per AUTH-1 (E2E-STAGE-1-03).

---

## 🟡 Deferred: AUTH-1's required-field UI (stories 02–06) not built yet

The readiness logic (US-AUTH-1-01: `computeStageReadiness`,
`computeMapReadiness` in `webapp/protype-2/src/readiness.ts`) is done and
tested, including a golden case read live from map 178. The UI that
*uses* it — required tags in the cell panel, the per-stage ready mark,
the map progress line, the checklist panel, and the Publish-version
button's disabled state — was not built this pass, for the same reason
as STAGE-1's row-switch toggle: no dev server was running and no browser
tool was used this session, and these are all visual changes to the
large, canvas-heavy `App.tsx`. Same standing rule: verify UI in a
browser before calling it done, don't just type-check blind JSX.
**Needs:** `npm run dev`, then wire stories 02–06 against the now-stable
`readiness.ts` API, checking each one renders and updates live.

---

## 🟡 Tracked: GOV-1 stories deferred because their tables don't exist yet

Not bugs — a sequencing finding. These stories target tables that later
epics create, so they were deliberately left undone rather than faked:

| Story | What it needs | Lands with |
|---|---|---|
| US-GOV-1-06 (duplicate audit + unique indexes on existing tables) | Only needed once ROLE-1/STAGE-1 add the real fields | ROLE-1 / STAGE-1 |
| US-GOV-1-07 (append-only enforcement tests) | `activity_log`, `plan_change_log`, `plan_publication`, `journey_map_version` | LOG-1 / LIVE-1 / PUB-1 |
| US-GOV-1-08 (concurrency / stale-write standard) | A second planner — single-planner MVP doesn't need it. `guards/assert_fresh` is **built and pushed, but not wired into any endpoint.** | whenever multi-planner lands |
| US-GOV-1-09 (atomic writes + failure injection) | The multi-row operations it covers (publish version, add job, publish to live) don't exist yet | PUB-1 / JOB-1 / LIVE-1 |
| US-GOV-1-10 (existing delete paths use guards) | `owner_lens_id` (STAGE-1) + `journey_map_version` (PUB-1) | STAGE-1 / PUB-1 |

**Rule going forward, already in the constraint matrix
(`docs/data-model-phase-4.md`):** each epic that creates a table also
writes its own integrity-audit check and its own delete-behaviour guard.
Don't retrofit all of GOV-1's remaining stories at the end — the checks
listed below need to be added to `ops/audit_integrity` as each table
lands:

- `work_item.status` disagrees with the status derived from its tasks (JOB-1)
- `work_task.stage_key` not found in its pinned `journey_map_version` (JOB-1)
- `planner_task_work_task` rows pointing at a missing planner task or work task (SCHED-1)
- A log row (`activity_log`) whose `work_task_id` doesn't exist (LOG-1)
- `plan_publication.snapshot_hash` no longer matching a recomputed hash (LIVE-1)
- Replaying a task's activity log disagrees with its stored status (LOG-1)
- A role (`actor_role`) referenced by a lens in a different account (ROLE-1)

---

## ✅ Fixed during the session (kept here for context, not action)

These were real live bugs, already fixed and verified — listed so the
*pattern* is remembered even though the instance is closed. Full detail
(exact error text, exact fix) is in `CLAUDE.md`.

- **The OBS-1 heartbeat task ran every 5 minutes for ~8 hours writing
  nothing.** `transform_timestamp` was called inside a `db.query` `where`
  clause, which compiles to SQL and can't call filter functions.
  `ops/health` had the identical bug and would have failed the first
  time it was opened. Both fixed; both smoke-tested afterward.
- `array.map` + `array.group_by` + `object.entries` with nested
  `$this[1][0]` indexing crashed on real (non-empty) data, despite
  matching the official documentation examples exactly. Rewrote with
  plain `foreach`/`array.push`/`|get`/`|set`.
- `db.query`'s `paging` does not produce a plain array — `foreach` and
  `[index]` both failed with `"Please use a numerically indexed array."`
- Omitted optional text/int inputs arrive as `""`/`0`, never `null`, so
  `?? fallback` was silently dead code in several places.
- A pipe nested inside a filter argument (`$map|get:($x|to_text):null`)
  parses but fails at runtime with `"Invalid expression"`.
- `mock` blocks inside a `db.get`/`db.query`, submitted via
  `createFunction`, were rejected outright on two different db action
  types.
- `redis.set { ... } as $x` is invalid — no `as` clause on `redis.set`.
- A multi-line boolean `where`/`precondition` (leading `&&`/`||` on its
  own line) failed to parse.

---

## 🟡 Reminder: P3A-1 is not a standalone epic

P3A-1 ("planner amendments") is listed as build-order step #0, but it's
not a thing to build on its own — it's a set of changes to apply **while
building phase-3** (step #8: `EPIC-PLN-1`…`PLN-8`). It archives/deactivates
instead of deleting, and adds the phase-4 columns (`is_archived`,
`plan_template_id`, `planner_agent.user_id`, `is_active`,
`tweak_reason`, nullable `title`) to phase-3's tables in their **first**
push, so there's no later migration.

**When phase-3 starts:** read `EPIC-P3A-1-planner-amendments.md`
alongside each phase-3 story (`PLN-1`, `PLN-3`, `PLN-5`, `PLN-6`,
`PLN-7`, `PLN-8` each have a one-line pointer to it already). Don't
build phase-3 first and bolt P3A-1 on after — the whole point is to
avoid a second migration.

---

## How to use this file

When picking up any of the 🔴/🟡 items: read the linked epic file in
`product/stories/phase-4/`, make the fix, then **move the entry here to
✅ with a one-line note on what changed and when** — don't delete it,
so there's a record of what was wrong and why.
