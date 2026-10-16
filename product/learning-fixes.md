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

## 🔧 Agreed 2026-10-14: stabilisation pass before phase-3

After PUB-1, the open items were triaged into "blocks future work" vs
"cosmetic or needs the founder". Agreed to fix the first group now, as a
pass of its own, rather than carrying them through six more epics:

| # | Item | Why it was picked | Status |
|---|---|---|---|
| 1 | New accounts' maps have `account_id = 0` | Breaks the entire feature-flag mechanism for any new customer — `publish_gate` and `required_fields_ui` could never be switched on for them | 🔴 **root cause found, needs your decision** — see below |
| 2 | `e2e/chat-session-crud.spec.ts` is truncated | Has made `npm run lint` red all session; a file that doesn't parse means the e2e regression gate can't run at all | ✅ fixed — and it was hiding 52 more errors |
| 3 | `clone_scenario` is broken | CLAUDE.md requires testing migrations/backfills on a **clone** of map 178, never the original. While broken, every epic has to hand-build scratch maps instead — PLN, JOB, SCHED and LIVE all need it | ✅ fixed, and the clone is now faithful |

**Deliberately NOT in this pass:** the duplicate "Task / Objective" field
and the unwatched Publish button (both fold into the next UI session), and
the two items that need the founder rather than a fix — the lost
validators (Xano dashboard only) and the orphaned-rows / delete-behaviour
decision.

### Related finding: the reserved table-number convention doesn't work

`product/stories/phase-4/README.md` reserves table ids for upcoming epics
(82 `journey_map_version`, 83–85 PLAN-1, 86–87 JOB-1, 88 SCHED-1, 89–90
LIVE-1, 91 LOG-1). **Xano assigns its own ids and ignores the reservation**
— PUB-1 asked for 82 and got 112, exactly as STAGE-1 asked for 109 and got
110/111. Phase-3's 74–79 collision (below) is the same problem seen from
the other side.

The numbers are not a plan, they're a wish. Every remaining epic will hit
this. **Recommendation:** stop reserving ids; record the id Xano actually
assigns, and name local files after it (which is already what happens in
practice). The phase-3 renumbering decision below then dissolves into the
same rule.

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

## ✅ Resolved 2026-10-14: the reserved table-number convention is retired

Decision taken (founder delegated it): **stop reserving table ids; record
the id Xano actually assigns.** The evidence is now unambiguous — three
epics in a row asked for ids and got different ones:

| Epic | Asked for | Got |
|---|---|---|
| STAGE-1 | 109 | 110, 111 |
| PUB-1 | 82 | 112 |
| PLN-1 | 74–79 | 113–118 |

Xano assigns ids on creation and ignores the plan. Local files are named
after the real id after the push, which is already what happens in
practice. `product/stories/phase-4/README.md`'s table list and
`docs/planner-data-model.md` now record real ids; the phase-3 renumbering
question below dissolves into this rule.

The original finding, kept for the record:

## ~~🔴 Needs a decision: phase-3's table numbering collides with live data~~

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

## ✅ Resolved 2026-10-14: `accessdenied` DOES keep its message over real HTTP

The open question below — "does `accessdenied` behave the same way through
a REAL authenticated HTTP call?" — got answered by accident while testing
PUB-1, and the answer **reverses the original finding**.

`apis/journey_map/520_..._readiness_GET.xs` has:

```
precondition ($journey_map.owner_user == $auth.id) {
  error_type = "accessdenied"
  error = "You don't have access to this map. (E-PUB-004)"
}
```

Called over real authenticated HTTP against another user's map, it
returned **403** with:

```json
{"code":"ERROR_CODE_ACCESS_DENIED","message":"You don't have access to this map. (E-PUB-004)","payload":""}
```

The custom message is intact. The stripping seen during GOV-1 was an
artefact of `runWorkspaceFunction`, which has no `$auth` context and no
real HTTP layer — not of `accessdenied` itself.

**What this changes:** guards may use the semantically correct
`accessdenied` (403) for authorisation failures instead of the
`inputerror` (400) workaround. Nothing needs rewriting — the existing
guards work and `inputerror` is not wrong — but new code should prefer
`accessdenied` where that is what it means. PLN-2's planner guards are
written that way.

**A caution this does raise:** `runWorkspaceFunction` is not a faithful
stand-in for an HTTP call. It has no `$auth`, and at least one error
behaviour differs. Function-level testing stays useful, but anything
about auth or error shape needs a real request.

The original finding, kept for the record:

## ~~🟡 Workaround adopted, not fully resolved: `accessdenied` strips the message~~

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

## ✅ Resolved 2026-10-14: STAGE-1/AUTH-1 UI built and verified with a real dev server + browser

The items previously tracked here (STAGE-1's planned-work toggle, AUTH-1's
required-field UI stories 02–06, and endpoints 211/517's end-to-end HTTP
path) are now built and live-verified — `npm run dev` + a real Chrome
session (disposable test account, scratch journey map), not just
type-checked. See EPIC-STAGE-1 and EPIC-AUTH-1's Test Results sections for
the full detail. Five real pre-existing bugs were found and fixed along the
way (stage ownership never reaching the frontend's state, a silently-saved
empty duration unit, a duration-pairing error on every owner save, a
touched-cell check fooled by decimal columns defaulting to 0, and the
planned-work toggle wrongly showing on non-actor rows) — all documented in
CLAUDE.md and the epic files so they aren't rediscovered.

## ✅ Decided and fixed 2026-10-14 (option A): signup never created an account

Found while testing PUB-1's gate (2026-10-14), **root cause traced
2026-10-14**. `ops/feature_enabled` keys on `account_id` and treats `0` as
"no account, flag off" — that part is correct fail-safe behaviour, not the
bug.

The actual chain, confirmed by reading the live rows:

| Record | account_id | Why |
|---|---|---|
| `user` 6 (a fresh signup) | **0** | ← the real cause |
| `journey_architecture` 38 | 0 | inherits from the user |
| `journey_map` 195 | 0 | `create_draft` correctly inherits from the architecture |

`apis/authentication/2_auth_signup_POST.xs` creates the user with name,
email, password and role — and **no account at all**. Nothing downstream
is broken; they are all faithfully inheriting a zero. The founder's own
account (id 2) was created by hand, which is why their maps work.

**Why this is a decision, not a fix:** it sets the data-isolation
boundary. The options are genuinely different products:

- **A — self-serve tenancy (recommended):** a signup creates its own
  `account` row and links the user. Matches how GOV-1's per-account flags,
  the Health page and `journey_map.account_id` are already modelled, and
  is the standard pattern. Teams would later join by invitation.
- **B — invite-only:** signup attaches to an existing account via an invite
  code; a signup with no invite has no account by design.
- **C — manual:** an admin assigns an account after signup.

**Founder chose A (self-serve tenancy).** Implemented and verified live
2026-10-14:

- `auth/signup` creates the account and the user in one transaction, and
  makes the user **admin** of their own account. Admin rather than member
  because `role == "admin"` is what gates editing your own account settings
  (api 134) and reading its event log (api 17) — a member would own a
  workspace they could not administer.
- `journey_architecture` POST and `journey_map/create_draft` now derive
  `account_id` from the authenticated user instead of accepting it as
  input. That was also a **tenancy hole**: a caller could place records
  inside someone else's account. `owner_user` was already derived from the
  token for exactly this reason.
- Signup's event log no longer passes the whole user record as metadata,
  which had been writing the hashed password into the log.

Verified over real HTTP: a fresh signup lands in its own account, and both
the with-architecture and no-architecture map paths inherit it.

**Backfill still open (low urgency):** the pre-existing zero-account rows
(`user` 6, `journey_architecture` 38) are leftovers from this session's own
QA signups, not customer data. `journey_map` 195 was pointed at the QA
account manually. Nothing needs backfilling unless real users signed up
before today — worth one check of `user` rows with `account_id = 0` before
launch.

---

## ✅ Fixed 2026-10-14: `clone_scenario` crashed, and was silently dropping data

Two problems, both fixed in `ai/tool/clone_scenario.xs` (tool 67):

1. **The crash** (`Unable to locate var: cell.stage_key`): the cell loop
   matched `$cell.stage_key` / `$cell.lens_key` against the new map's keys,
   but a `journey_cell` row has no such columns — it has `stage` and `lens`
   integer ids. The remap now goes id → key (source map) → id (new map).
2. **Silent data loss, the worse half:** the clone dropped every field added
   since the tool was written — cell durations (TIME-1), stage ownership and
   the planned-work switch (STAGE-1), lens cost rates, and the stage's
   `primary_actor_lens`. A clone missing those reads as "no owner, no
   duration", which would have made PUB-1's gate and AUTH-1's readiness look
   broken *on a clone* when they were fine.

**Verified:** cloned map 178 → map 196, then ran PUB-1's snapshot builder
over both. The snapshots are identical except the title — same stages, same
owners, same actor types, same planned-work values, same cell content. The
gate then reported `OWNER_NOT_WORK_ROLE` for stages 1–4 and 7 on the clone,
which is FT-PUB-1-04 verified against a real clone rather than a fixture.

**Caveat:** map 178 has no durations filled in, so duration cloning is in
the copy list but not yet proven by a case that would have caught its
absence.

**Note:** map **196** is that test clone, sitting in the founder's real
architecture 31. Harmless (draft, nothing pins to it) but visible in the
UI — delete it whenever.

---

## ✅ PUB-1 review pass, 2026-10-14 (Opus): two findings, both fixed

Done as the review the model-guidance table asks for after an Opus-marked
epic. Two things the build pass had got away with:

**1. The content hash depended on database ids, not content.** Cells came
straight out of a `sort = {stage: "asc", lens: "asc"}` query — ordered by
id. Since `pub/canonical_hash` takes array order as given, that meant
deleting a row and re-adding it with the same key (new, higher id) would
re-sort the cells and change the map's hash even though nothing a user can
see had changed. Harmless today (the hash is only compared against a
stored snapshot of the same map) but it would have made **stale detection
report false positives** the moment US-PUB-1-05's deferred half lands.

Fixed: cells are now emitted by walking the already-ordered stages × rows,
so the order follows the definition rather than the id sequence.
**Verified backward-compatible** — map 195 still hashes to
`1602242c8061…`, the exact value stored in its existing version rows, so
nothing already frozen was invalidated.

**2. The dual hash had only ever been tested on ASCII.** Both pinned
goldens were plain English, so a UTF-8 encoding difference between
`TextEncoder` in the browser and `sha256` on Xano would have sailed
through — and a map title with an accent in it is not an edge case. Tested
with accents, an em dash, CJK and an emoji (a surrogate pair):
byte-identical on both sides, `dc1dc9e5…`. Now pinned as a third golden in
`versionHash.test.ts`.

### Noted, not fixed: snapshot building does full table scans

`pub/build_map_snapshot` reads **all** of `journey_stage_owner` with no
filter, because that table has no `journey_map` column (STAGE-1's
side-table workaround). Same shape as the frontend's
`listJourneyStageOwners`. Fine now — one row per owned stage across the
whole system — but it grows with every map in every account, and it runs
on every publish *and* every readiness check. Worth a `journey_map` column
(or a join) before there are thousands of maps. Not urgent, and not worth
an `updateTableSchema` against a table with validators today.

---

## 🔴 Needs a dashboard edit: two planner enum columns have no default

`planner_timeline.status` and `planner_task.status` (PLN-1) were specified
with defaults `draft` and `planned`. Both shipped without one, so a
**direct** insert leaves `""` — not even a member of the enum.

No API-created row can hit this: PLN-6 and PLN-7 write `status` explicitly
on every create. But the schema is wrong, and the only ways to fix it are
`updateTableSchema` (which silently drops the four `trim` validators on
`planner_task` — the documented bug above) or deleting and recreating the
table. Neither is worth doing unilaterally, and the MCP surface has no
single-column update.

**Needs:** add the two defaults in the Xano dashboard. Five minutes, and
it closes the last gap in PLN-1's FT-PLN-1-07.

---

## 🧠 Worth knowing: there are no real nullable foreign keys in this workspace

Not a bug — a property of the platform that keeps reshaping designs, so
it belongs written down once. An `int` column here cannot hold a true
`null`; it defaults to `0`. Every "nullable FK" in every epic is really
"`0` means not set":

- `planner_task.timeline_id = 0` → backlog
- `planner_task.assignee_agent_id = 0` → inherit the timeline's agent
- `planner_agent.model_id = 0` → no model
- `planner_agent.user_id = 0` → no login
- `planner_workspace.plan_template_id = 0` → not from a template

**The consequence that bites: you cannot put a unique index on a nullable
FK.** In a normal database many rows can share `NULL` there; here they all
share `0` and collide. This already invalidated one written spec —
US-P3A-1-01's `unique (workspace_id, user_id)` on `planner_agent` would
have rejected the second login-less agent in every plan. Caught by
inserting two of them.

**Rule for the remaining epics:** when a spec asks for a unique index that
includes an optional reference, it cannot be built as specified. Enforce
it in the API and say so in the table's header comment.

---

## 🧠 Worth knowing (PLN-2): a function's header comment **is** its `description`

They are one field, not two. Writing both — the repo's usual "rich
comment block, then `description = "..."` inside the function" — makes
Xano **concatenate** them into a single description blob, and the
`description =` statement itself vanishes from the source on round-trip.

Pushed PLN-2's `resolve_actor` that way and got back a description that
was the ten-line comment with the one-line summary stuck on the end, and
a `.xs` file with no `description` statement in it at all.

**Do:** write the header comment and nothing else. It round-trips exactly
(the only artefact is a double space after `//`), so the local file and
the live function stay diffable — which is the whole point of
`CLAUDE.md`'s "fetch live and diff before pushing" rule.

**Do not:** add `description =` to a function that already has a header
comment. `functions/guards/*.xs` and several others still do this; their
live descriptions are doubled. Harmless, cosmetic, not worth a sweep —
just don't copy the pattern into new files.

---

## 🧠 Worth knowing (PLN-2): a test suite of only rejections proves nothing

PLN-2's eight planned functional cases were **all** negative — "this
should be refused". A guard hard-wired to `throw` unconditionally would
have passed all eight while blocking the entire planner for everyone.

Added a positive-path case per entity guard (`assert_agent(3,1)` and
`assert_task(3,1)` return the row *and* its workspace) before calling the
epic done.

**Rule for the remaining epics:** any time a story's test table is all
rejections — guards, validation, permission checks — add the "and the
right caller still gets through" case. It is the one that catches a
fail-closed bug, and specs written from a security angle routinely omit
it. Applies directly to GOV-1's guards and LOG-1's status engine.

---

## 🟡 Re-verify after a re-push, even a comment-only one

PLN-2's guards were verified, then all seven were re-pushed to fix the
`description` duplication above, then **re-verified from scratch**. The
second run was not ceremony: the first run's evidence belonged to code
that no longer existed, and a push that returns no parse error is not
proof the logic survived (CLAUDE.md already says this for new pushes —
it applies equally to edits that "only" touch comments).

All eight cases plus the two positive-path checks were green both times.

---

## 🔴 Needs your approval: five delete paths, one nightly job, sixteen scratch functions

The planner backend is otherwise complete. Everything below is written,
reviewed and commented; none of it has been pushed, because CLAUDE.md
says to ask before any delete, and the session's permission layer
independently refused those pushes too.

| File | What it does | Blocks |
|---|---|---|
| `functions/planner/delete_workspace_cascade.xs` | Delete a plan and its children | FT-PLN-3-07/08/09 |
| `functions/planner/delete_model_guard.xs` | Refuse to delete a model agents still use, naming them | FT-PLN-4-08/09 |
| `functions/planner/delete_agent_cascade.xs` | Remove an agent, returning their work to the backlog | FT-PLN-5-07/08/09 |
| `functions/planner/delete_timeline_cascade.xs` | Delete a day, returning its tasks to the backlog | FT-PLN-6-11 |
| `functions/planner/delete_task.xs` | Delete one task and close the gap | FT-PLN-7-16 |
| `tasks/20_planner_integrity_audit.xs` | Nightly audit across accounts | FT-PLN-8-07 |

**Added 2026-10-15 (LOG-1): two scratch functions to delete.** These are
live in the workspace now, not files — they were created to run LOG-1's
tests and should not stay.

| Live function | Why it exists | Risk if left |
|---|---|---|
| `scratch/verify_transitions` (133) | Walked all 35 (status, event) pairs so the live table could be diffed against the TypeScript | None — read-only |
| `scratch/tamper_task_status` (137) | **Writes a task status bypassing the event engine**, to prove the replay audit catches tampering | Real. It is the exact thing the audit exists to detect. Not reachable over HTTP (workspace functions have no route), but it should go. |
| `scratch/recent_app1_events` (142, added APP-1) | Read-only, lists `event_log` rows for `feature = "APP-1"` — used to verify the OBS-1 pipeline fix below | None — read-only |
| `scratch/parse_timestamp_probe` (143, added VAR-1) | Read-only, confirmed `parse_timestamp`/`add_secs_to_timestamp` behave as documented | None — read-only |
| `scratch/nested_conditional_probe` (145, added VAR-1) | Read-only, isolated a nested-conditional question while debugging | None — read-only |
| `scratch/zero_vs_null_probe` (146, added VAR-1) | Read-only, confirmed the critical `0 == null` finding below | None — read-only |
| `scratch/var1_check` (148, added VAR-1) | Read-only, lists `event_log` rows for `feature = "VAR-1"` and confirms row counts are unchanged by reading variance | None — read-only |
| `scratch/claim_map` (149, added E2E-1) | Patches `owner_user`/`account_id` on a map created via the journey-map MCP tool, which has no auth context | Low — a scratch write, but only ever run against E2E-1's own test maps |
| `scratch/enable_flag` (150, added E2E-1) | Enables an `account_feature_flag` row by account+key | Low — generic flag toggle, same shape as the product's own mechanism |
| `scratch/add_workspace_map` (151, added E2E-1) | Inserts a `planner_workspace_map` row directly — works around the missing "add a map to an existing plan" endpoint above | Low — same effect a real endpoint would have, just without the guard rails one might add |
| `scratch/disable_flag` (152, added E2E-1) | Created, never actually invoked (see the flag decision above) | None |
| `scratch/inspect_recent_events` (153, added E2E-1) | Read-only, lists the most recent `event_log` rows — this is what surfaced the password-logging bug above | None — read-only |
| `scratch/scrub_auth_metadata` (154, added 2026-10-16) | **Already run** (2,626 rows cleaned, with your go-ahead) — the write capability stays live until deleted | None left to do, but it's still a function that can write; delete once reviewed |
| `scratch/verify_scrub` (155, added 2026-10-16) | Read-only, confirmed zero rows still over-exposed after the cleanup above | None — read-only |
| `scratch/json_patch_probe` (156, added 2026-10-16) | Read-only-in-effect (writes a throwaway row, never a real one), proved the merge-vs-replace finding in `CLAUDE.md` | None |

Deleting a function is still a delete, so all sixteen are waiting on you.

**Also worth adding to the nightly job when it is approved:**
`ops/audit_execution` (live, function 136) — the execution-layer twin of
`ops/audit_integrity`. It is what proves the record is trustworthy, and
right now nothing runs it on a schedule.

**Three things worth knowing before you decide:**

1. **Only `delete_task` actually destroys work.** Deleting a plan, an
   agent or a timeline all keep every task — they move to the backlog.
   That one deserves a confirmation step in the UI; the others do not.

2. **The risky half of each cascade is already proven.**
   `planner/return_tasks_to_backlog` and `planner/resequence` contain
   no deletes, so they were pushed and tested. What remains unverified
   is only the `db.del` calls themselves.

3. **`PLN-8`'s audit is the thing that will check them.** It is live
   and already catches orphans, cross-workspace links and seq gaps — so
   when the deletes are approved, the way to verify them is: run a
   cascade on the throwaway fixture (account 6, plans 4 and 5), then
   run `GET planner/workspace/integrity` and expect `clean: true`.

**One genuine unknown remains:** whether `db.del` removes every
matching row or only the first. `db.patch` provably removes only the
first (see below), and all five files are written on the assumption
that `db.del` behaves the same — looping and deleting by id. That
assumption should be confirmed on the fixture before the cascades are
trusted.

**The nightly job** is separate from the deletes: it is standing
configuration rather than a destructive action, and the only reason it
is held is that a recurring job runs unattended forever once created.
It should not share an hour with `19_ops_integrity_audit`.
- **Already prepared:** a throwaway plan (account 6, ws 4 — 2 agents,
  3 timelines, 6 tasks, 2 backlog) and a sibling plan (ws 5) that must
  survive, so verification is one push and one test run.
- **One genuine unknown to test first:** whether `db.del` with
  `field_name`/`field_value` deletes *every* matching row or only the
  first. CLAUDE.md only documents the single-record case. If it deletes
  one, each child delete has to become a loop.

Same question will come up again at PLN-5 (agents) and PLN-6
(timelines), so it is worth settling once.

---

## 🟡 Scratch functions left in workspace 1, safe to delete

Created while probing XanoScript behaviour for PLN-3, all named
`scratch/*` and called by nothing:

`scratch/count_probe` (105), `scratch/seed_cascade_fixture` (108),
`scratch/date_probe` (109), `scratch/in_probe` (110),
`scratch/mint_test_token` (111), `scratch/tally_probe` (112).

Not deleted here because CLAUDE.md says to ask first. `mint_test_token`
is the one worth removing soonest — it mints an auth token for any user
id, which is fine as a dev probe and not something to leave lying
around.

Test data also left behind, deliberately: account 6 plans **4** and
**5** (the cascade fixture) are needed to finish PLN-3's delete tests.
Plans **6, 7, 8** in the same account are leftovers from testing and can
go any time.

**Added 2026-10-15 (APP-1), workspace 9 (account 6):** agent **15**
("Second Agent APP1", unlinked, created to test the one-login-per-agent
clash); timeline **18** (2026-10-15, agent 14) and work_item **4**
("APP-1 live demo job", with work_tasks 9–10) — a genuinely fresh,
published job used to prove Start/Done/Blocked work in a real browser
rather than replaying already-finished test data. All harmless, all
visible in the UI, all safe to delete whenever.

---

## 🔴 Never use the MCP `updateTableContentItem` tool — it corrupts rows

Calling it with one field (`{user_id: 9}`) on an agent row **also
reset that row's `workspace_id`**, silently moving the agent into a
different plan. Supplying `workspace_id` back explicitly in a second
call did **not** fix it.

Repaired with a throwaway function using `db.patch`, which worked
immediately and correctly.

**For any ad-hoc row edit, write a scratch function with `db.patch`
and run it with `runWorkspaceFunction`.** The tool's own description
says it is destructive — this is what that means in practice.

Found in LIVE-1 while linking a login to an agent. The corruption was
caught within a minute only because the next test failed oddly; a
quieter change could easily have gone unnoticed.

---

## 🟡 Two integrity checks PLN-8's audit still needs

Both surfaced while building the epics that created the data:

- **JOB-1 (FT-JOB-1-G05):** a `work_task` whose `stage_key`/`lens_key`
  does not exist as a cell in its job's pinned version.
- **LIVE-1 (FT-LIVE-1-G06):** a timeline marked `published` with no
  `plan_publication` row, or a publication whose stored
  `snapshot_hash` does not match a re-serialisation of its snapshot.

Neither is implemented. They belong in `planner/audit_tasks` (or a
new `audit_jobs`) and a new `audit_publications`, following the same
two-pass shape as the existing checks. Worth doing as one small pass
rather than piecemeal.

---

## 🔴 GOV-1's stale-write guard cannot work on any planner table

`guards/assert_fresh` (standard S12) compares the `updated_at` a
caller last saw against the row's current one. **Every planner table
declares `updated_at` as a `date`** — day granularity, e.g.
`"2026-10-15"`.

So two people editing the same row ten minutes apart produce an
identical `updated_at`, and the guard would pass the second write
while reporting success. Using it there would be worse than not using
it, because it would look like protection.

Found in SCHED-1, the first epic to ask for stale-write detection.

**What SCHED-1 does instead:** value-based concurrency — the caller
sends the duration it last saw, and the write is refused if the row
has moved on. Narrower (it only fires when the field being changed
actually moved) but true. Verified live.

**To switch S12 on properly**, `updated_at` must become a `timestamp`
on `planner_workspace`, `planner_agent`, `planner_timeline`,
`planner_task`, `work_item` and `work_task`. That is a column type
change on tables carrying `trim` validators, so it runs into the same
`updateTableSchema` problem as the other open schema items — it needs
the Xano dashboard, or the side-table trick.

---

## 🧠 Worth knowing (JOB-1): `enum x?=value` DOES set a working default

PLN-1 recorded two planner enum columns as having no default and read
it as a platform limitation. It was a syntax problem. JOB-1 created
`work_item.status` and `work_task.status` with `enum status?=open` and
`enum status?=not_started`, and both came back with the default in
place and working.

**Use `enum field?=value` at CREATE time** for any new enum column.

This does **not** fix the two existing columns
(`planner_timeline.status`, `planner_task.status`): changing them in
place still needs `updateTableSchema`, which would drop their tables'
`trim` validators. They remain on the open list — but the API writes
both explicitly on every create, so no API-created row can miss one.

---

## 🔴 Latent bug in existing code: `|contains:` on an array is always false

`|contains:` returns **`false` for every array** — value present or
absent, literal or variable. Confirmed live across four combinations.
It is a string-substring filter; on an array it is not merely wrong, it
is wrong in the direction that reads as "not found". `index_of` and
`in_array` do not exist either.

Found when PLN-5 handed every new agent the same colour.

**Four existing uses are on arrays and are therefore doing nothing:**

| File | Line | What it was meant to do |
|---|---|---|
| `apis/journey_map/76_..._export_linked_graph_GET.xs` | 90, 111, 150 | `!($visited|contains:X)` — the **cycle/duplicate guard** of a breadth-first graph walk |
| `apis/journey_map/130_..._build_full_POST.xs` | 220 | `$builder_phase_indices|contains:$loop_idx` |

The export one is the worrying one: `$visited` never reports a hit, so
every edge re-adds its target to the frontier on every round. On a map
graph with a cycle or even a diamond it re-walks nodes and duplicates
output, bounded only by whatever depth cap that endpoint has.

**Not fixed here, deliberately** — both are live endpoints unrelated to
the planner, and rewriting a graph traversal unsupervised is riskier
than flagging it. Needs a decision: fix them, or confirm they are
unreachable.

The other seven uses in the repo are on **strings** (search text, a log
message) and are fine.

**The rule going forward:** test array membership with a `foreach` loop,
or with `x in $arr` inside a `db.query` `where` clause (that form does
work — it compiles to SQL).

---

## 🧠 Worth knowing (PLN-6): a `conditional` can silently void its own writes

**A `conditional` inside a `foreach`, whose CONDITION reads a variable
that was `var.update`d earlier in the same iteration, discards
everything the branch writes.** No error, no warning — the endpoint
returns 200 with plausible, wrong numbers.

Isolated with three tallies over identical data:

| the condition reads | result |
|---|---|
| the loop item (`if ($r.flag == true)`) | ✅ correct |
| a constant (`if (true)`) | ✅ correct |
| a var updated earlier in that iteration (`if ($cur != null)`) | ❌ **all writes lost** |

Found because PLN-6's timeline list reported `task_count: 0` for every
timeline while the database plainly had tasks.

This also explains why the existing working code is fine:
`functions/ops/group_issues.xs` and PLN-3's plan list both branch on
the **loop item**, never on a var they just set.

**The rule:** only branch on the loop item, on an input, or on a
variable set before the loop began. If the branch exists to skip
unknown keys, change the query so the skip is unnecessary instead —
`apis/planner/539_workspace_workspace_id_timeline_GET.xs` scopes its
task query with `timeline_id in $tl_ids` for exactly that reason.

---

## 🧠 Worth knowing (PLN-6): an omitted optional `date` input does not exist

`text` and `int` arrive as `""` and `0` when omitted. An omitted
optional **`date`** is not there at all — referencing it fails at
runtime with `"Unable to locate input: date_from"`.

Worse on a **GET**: there is no JSON body, so the usual
`util.get_raw_input|has:"x"` presence trick does not work either.

**The fix:** declare optional date filters as `text` (they default to
`""`, which is testable) and widen the bound to a sentinel —
`"0001-01-01"` / `"9999-12-31"` — when absent. Comparing a text date
against a `date` column in a `where` clause works fine.

---

## 🧠 Worth knowing (PLN-5): `db.patch`/`db.del` only touch the FIRST match

`db.patch` with `field_name`/`field_value` updates **one** row, not
every match. There is no "patch where" form. Confirmed live: PLN-5's
"hide all" patched by `workspace_id` and flipped exactly one of six
agents, returning `200` with no hint anything was skipped.

`db.del` takes the same form and almost certainly behaves the same way.

**This nearly shipped a data-corruption bug.** PLN-3's
`delete_workspace_cascade` was written as one `db.del` per child table
by `workspace_id`. Had it been pushed, deleting a plan would have
removed one task, one timeline, one agent and then the plan — leaving
every other child orphaned against a plan that no longer existed. It
has been rewritten to read each child set and delete by id.

**The rule:** to write or delete many rows, `db.query` them, then loop
patching/deleting by `id`, inside a `db.transaction`.

---

## 🧠 Worth knowing (PLN-3): `|get` with a VARIABLE key ignores its default

The single nastiest XanoScript trap found so far, because it fails
silently and produces plausible-looking output.

| expression | result |
|---|---|
| `{}\|get:"nope":0` | `0` ✅ |
| `{}\|get:$k:0` (where `$k` is `"nope"`) | **`null`** ❌ |
| `$filled\|get:$k:0` (key exists) | the value ✅ |

So a lookup with a variable key works **only when the key is already
there**. On a miss the default is thrown away and you get `null`.

Found because every count in PLN-3's plan list came back `null`. The
tally loop did `|get:$key:0` → null → `null + 1` → null → stored null.
No error anywhere; the endpoint returned 200 with a well-formed body
full of nulls.

**Why `functions/ops/group_issues.xs` gets away with it:** it passes
`|get:$fp:null`. Its default *is* null, so the bug is invisible there.
CLAUDE.md cites that file as the safe grouping pattern — it is, but
only by luck on this point.

**The rule:** never rely on `|get`'s default with a variable key. Either
pre-seed every key you will look up (what
`apis/planner/524_workspace_GET.xs` does — seed each plan's tally to 0
before counting), or test for null explicitly afterwards.

---

## 🧠 Worth knowing (PLN-3): a token minted via `runWorkspaceFunction` is not valid

`security.create_auth_token` called through `runWorkspaceFunction`
produces a token the live API rejects with `"Invalid token."`, even
though the call is byte-identical to the one in `auth/login`. Tokens
appear to be signed per execution context.

**To get a usable token for real-HTTP testing without touching a
password:** run `Getting Started Template/generate_magic_link` for the
test user's email via `runWorkspaceFunction` (this writes a hashed
one-time token to the user row and sends no email), then POST the
returned plaintext token to `reset/magic-link-login` over real HTTP.
That returns a genuine, live-signed `authToken`. Used for all of PLN-3's
testing.

---

## ✅ Resolved 2026-10-14 (PLN-3): `inputerror` does NOT prefix its message

PLN-2 flagged that `assert_same_workspace` returned
`"Param:  - Entities must belong to the same workspace"` and worried it
broke VAL-1 across five existing guards.

**Over real HTTP the message is clean.** PLN-3's endpoints returned
*"You already have a plan with this name. (E-PLN-001)"* and
*"The end date can't be before the start date. (E-PLN-002)"* with no
prefix at all. The `Param:` prefix is an artefact of
`runWorkspaceFunction`, exactly like the `accessdenied` case PUB-1 hit.

**The standing lesson (now twice confirmed): never judge an error
message by what `runWorkspaceFunction` prints.** It distorts both the
message text and the error shape. Check user-facing wording over real
HTTP or not at all.

---

## ~~🟡 Needs a real HTTP test (PLN-3): `inputerror` prefixes its message~~

`planner/assert_same_workspace` returns
`"Param:  - Entities must belong to the same workspace"` rather than the
clean sentence. VAL-1 requires friendly messages, so if that prefix is
real it is a VAL-1 violation — and it would affect **every** existing
`inputerror` guard: `guards/assert_state`, `guards/assert_fresh`,
`guards/assert_not_archived`, `ops/build_diagnostic_bundle`. Pre-existing
and codebase-wide, not introduced by PLN-2.

**Not chased yet, on purpose.** PUB-1 already proved
`runWorkspaceFunction` distorts error shape — `accessdenied` appeared to
strip its custom message there, and real HTTP showed it did not (see the
resolved entry above). The prefix may be the same kind of harness
artefact. Checking it needs a real endpoint, and PLN-3 builds the first
one.

**At PLN-3:** call an endpoint that trips an `inputerror` over real HTTP
from the browser and look at the actual response body. If the prefix is
real, fix it once, centrally, for all five call sites.

**Done 2026-10-14 — the prefix was not real.** See the resolved entry
above. No fix was needed.

---

## 🟡 No way to run a `workflow_test` from a session

`runUnitTest` only accepts unit tests attached to a function/query/
middleware — passing a workflow-test id returns "Unit test not found" —
and the MCP surface exposes no `runWorkflowTest`. So `workflow_tests/*.xs`
files can be written and pushed but never executed from here. This now
affects `16_publish_version.xs` (PUB-1) as well as the older
`25_observability.xs`, and it is why FT-PUB-1-13 (the `workflow_tests/1–9`
regression sweep) could not be run.

**Compensated by:** driving every assertion in `16_publish_version.xs`
individually through `runWorkspaceFunction` — all passed. **Needs:** a way
to run workflow tests (a Xano dashboard run, a CI step, or a different
tool) before the completion gates that depend on them can be honestly
called green.

---

**Still open:** `ai/tool/update_stage_contract.xs` (tool 70)'s own
MCP-call assembly remains unverified end-to-end — this pass covered the
HTTP/browser path (endpoints 211, 517), not the AI-tool-call path. Same
open gap as VAL-1's `ops/feature_flag`. Needs an authenticated MCP-tool-call
test once that's possible.

**New minor cosmetic gap, not blocking:** the Internal Employee template's
own field list repeats "Task / Objective" below AUTH-1's new required Task
field — same underlying `actor_fields.task_objective` key, shown twice in
the cell panel. Harmless (both read/write the same value) but worth hiding
the template's own copy of that one field when the required block already
shows it.

---

## ✅ Fixed 2026-10-14: `npm run lint` was blind, and `@types/react` had never been installed

`webapp/protype-2/e2e/chat-session-crud.spec.ts` was **truncated** — 148
lines ending mid-block, missing the closing `});` for its `test.describe`.
TypeScript stops at a parse error, so for however long that file has been
broken, `npm run lint` has been reporting exactly one failure and
type-checking **nothing past it**. The build protocol leans on lint as a
regression gate; that gate has been switched off without anyone knowing.

Fixed the brace (2026-10-14). The type-check then ran for real and found
**53 errors**. Seven were in files this session touched and are fixed:

| File | Was |
|---|---|
| `readiness.test.ts` ×2 | `Object.freeze` gives a `readonly` array; `computeStageReadiness` demanded a mutable one. Signatures now take `readonly` — correct for pure functions anyway |
| `App.tsx` ×2 | `new Map(lenses.map(...))` inferred as `unknown`; annotated explicitly |
| `StageEditPanel.tsx` | `React.MouseEvent` with no `React` import |
| `xano.ts` | `XanoJourneyMap` widened `map_level` to `string` while extending `JourneySettings`, which narrows it — an invalid override |
| `xano.ts` | **A real defect:** `authXanoRequest` constructed `XanoHttpError` without the required correlation id, so auth failures carried no Reference for the user to quote. Now generates and sends one like every other request |

The other 46 were pre-existing, in code this session had never opened. All
46 are now fixed too — **`npm run lint` exits 0 for the first time**.

**The root cause of most of them: `@types/react` was never installed.**
React 19 ships no type definitions of its own, and nothing in
`package.json` supplied them, so for the whole life of this codebase the
entire React API has been implicitly `any`. That is what produced:

| Symptom | Count | Real cause |
|---|---|---|
| `Cannot find namespace 'React'` in 7 planner components | 31 | no React types |
| `Property 'key' does not exist on type 'XProps'` | 3 | no JSX typings, so React's reserved `key` prop wasn't known |
| `Array.from(selected)` degrading to `unknown[]` in `ScenariosTab` | 2 | `useState<Set<number>>`'s generic was lost through an untyped hook |

Installing `@types/react` / `@types/react-dom` (v19, dev-only) fixed those
and — the genuinely surprising part — **surfaced nothing new**. The fear
was that real types would expose hundreds of latent errors; the count went
straight from 3 to 0. The code was written correctly; it had simply never
been checked.

The rest were real and are fixed:

- **`ops/logEvent.ts` — a live bug, not a type nit.** It does
  `const {xanoRequest} = await import('../xano')`, but `xanoRequest` was
  never exported, so the import resolved to `undefined` and **every
  client-side event send threw**. OBS-1's browser event pipeline has never
  delivered a single event; `failure` events were accumulating in the
  localStorage offline buffer (`ops_offline_event_buffer`) with no way to
  drain, since flushing used the same broken call. Fixed by exporting it.
- **`e2e/chat-validation.spec.ts` ×4:** called `openChat(page)`, but this
  file's helper is named `openFreshChat`. A second broken spec, hidden
  behind the first.
- **`validation/*` ×3:** `if (result.ok)` does not discriminate
  `ValidateResult` here, because **tsconfig.json enables neither `strict`
  nor `strictNullChecks`**. Added explicit `isValidationFailure` /
  `isValidationSuccess` type guards, which narrow regardless of strictness.
- **`ArchitectureDetail` ×2:** optimistic rows cast a clone *summary* to a
  full `XanoJourneyMap`. Now cast through `unknown` with a comment, which
  is what is actually happening.

### Still worth deciding later (not urgent)

`tsconfig.json` has no `strict`, `strictNullChecks` or `noImplicitAny`.
The gate is green, but it is a weak gate — the `ValidateResult` narrowing
failure above is exactly the kind of thing it lets through. Turning
`strict` on now would be a large, separate piece of work; worth doing
deliberately rather than as a side effect.

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

## 🧠 Worth knowing (LOG-1): the stage's "done" flag is computed, not stored

The epic says a stage advances when its completion rule is satisfied, which
reads like it wants a `stage_status` to write to. It doesn't get one.

Two caches already shadow the activity log — `work_task.status` and
`work_item.status` — and each one is a thing that can silently drift and
therefore has to be audited every night. A third would buy nothing: "is
every task in this stage finished" is a count over rows we are already
reading, and a count cannot drift. `log/stage_progress` derives it on
read, and the record-event endpoint returns it inline so the performer
app learns "stage finished" without a second call.

**The rule for the next epic:** before adding a column that caches a
fact, check whether the fact is a count or a comparison over data you
already have. If it is, derive it. Every cache is a promise to audit it
forever.

---

## ✅ Fixed during LOG-1: the transition table was in two places

LOG-1's first version put the status transition table inside the
record-event endpoint, and the replay audit — written an hour later —
had its own copy.

That is the one duplication that actually matters here. **An audit
holding its own copy of the rule it audits will eventually disagree with
the engine, and it will sound exactly as certain when it is the one
that's wrong.** It would report healthy data as broken, or miss real
tampering, with no way to tell which from the output.

Extracted to `log/next_status` (one backend copy, called by both), and
the same move applied to job status: `log/derive_job_status` is
read-only and `log/sync_job_status` is now just the writer on top of it.
Verified by walking all 35 (status, event) pairs through the live
function and diffing against `logModel.ts` — all 35 matched.

---

## 🟡 Stated limit (LOG-1): assignment is enforced only where assignment exists

`POST work_task/{id}/event` denies an event with `E-LOG-003` when the
task is scheduled onto a named person's day and the caller is neither
that person nor an account admin.

**Where no one is assigned, it does not deny.** `planner_agent.user_id`
is 0 until an agent is linked to a login, and most still are, so denying
unassigned work would stop everything rather than protect anything.
Account-level tenancy still applies to every call, so this is "no one
specific to check against", not "no check".

This tightens by itself as APP-1 makes assignment normal. **Flagging it
because it is an authorisation rule that is weaker than it looks** — if
you want it strict before APP-1, that is a one-line change plus a
backfill linking agents to logins.

---

## 🟡 Not proven (LOG-1): the rollback on a failed log write

The log row and the task's status are written inside one
`db.transaction`, so a failure part-way should leave neither. **That is
argued from the code, not demonstrated.** Simulating a mid-transaction
failure needs Xano's unit-test `mock` blocks, which this workspace
rejects for any function pushed through the MCP tool.

It is the most important write path in the product, so the gap is worth
naming rather than burying in a test table. Two ways to close it when
you want to: build the mock in the Xano dashboard by hand, or add a
deliberate constraint violation behind a flag that only a test can set —
the second one is more honest about what it is, but it does put a test
switch in a production endpoint, which the test conventions forbid.

---

## ✅ Closed during LOG-1: two audit checks earlier epics left open

`ops/audit_execution` (function 136) is the execution-layer twin of
`ops/audit_integrity`, and it picks up the two checks that were carried
forward: **JOB-1 FT-G05** (a job whose stored status disagrees with its
tasks) and **LIVE-1 FT-G06** (a publication whose timeline is gone). It
also adds LOG-1's own replay check, log orphans, and log rows whose
denormalised job disagrees with their task.

It is separate from `ops/audit_integrity` rather than added to it
because PLN-8 already showed this workspace rejects a single audit
function once it grows past a certain size.

**Nothing runs it on a schedule yet** — that is part of the nightly job
still waiting on approval above.

---

## 🔭 Holistic flags, 2026-10-15 — noted, NOT acted on

Founder asked for a whole-system look before APP-1, with findings written
down rather than fixed. Ordered by how much they'd hurt if left. Nothing
below has been touched.

### 🔴 1. The chain breaks in the middle: the planner UI never talks to Xano

The data flow is **map → plan → job → schedule → publish → execute**.
Verified today in `webapp/planningFrontendv2`: **zero `fetch` calls, zero
`axios`, no HTTP client in `package.json` at all** — state lives in
`localStorage` (`src/App.tsx`, `src/data/initialData.ts`).

So of the three modules:

| Module | Backend | UI | Wired together |
|---|---|---|---|
| Intelligence (journey map) | ✅ | ✅ | ✅ |
| Planning | ✅ PLN-1…PLN-8, 41 endpoints | ✅ exists | ❌ **not connected** |
| Execution | ✅ LIVE-1 + LOG-1 | APP-1, next | will be ✅ |

**Why this matters more than it looks:** the planner is the module that
*feeds* execution. If no one can create a plan or publish a day through a
UI, then APP-1 ships correct and has nothing real to display — the only
way to get work in front of a performer is by calling the API by hand.
The two ends of the chain will be wired and the middle will not.

**There is no epic for this.** The build order goes straight from LIVE-1
to APP-1. A "PLN-9: wire the planner frontend" has been mentioned in
passing but was never added to `product/stories/phase-4/README.md`.

#### ✅ Decided 2026-10-15 (founder delegated): APP-1 first, PLN-9 next

Reasons, in order of weight:

1. **PLN-9 is unscoped.** It has no epic, no stories, no test plan. The
   planner UI is a localStorage prototype, so wiring it means mapping its
   whole state model onto 41 existing endpoints. Scoping that honestly is
   a task in itself. APP-1 is fully specified and small.
2. **APP-1 is demoable on its own.** Published days can be seeded through
   the API, so "here's Monday, tap start, tap done, watch it recorded" is
   a real demo of the execution module. PLN-9 first would give the
   opposite — a planner that writes to the real database with nothing
   downstream to receive it.
3. **Building APP-1 first informs PLN-9.** The performer app is the first
   real consumer of the published-day shape; whatever it finds awkward is
   exactly what PLN-9 should fix rather than faithfully reproduce.
4. **The timezone seam has to land in APP-1 anyway** (item 4 below).

**PLN-9 should be written up as a proper epic before it starts**, not
picked up ad hoc — it is the largest remaining unknown in the build.

### 🔴 2. Three modules in your head, two apps on disk

Founder describes the product as three modules and the execution one as
"a mobile app". The build order currently puts APP-1 as a **route inside
the journey-map app** (`webapp/protype-2`).

That's a mismatch worth settling before APP-1 rather than after:

- A performer is a different person from a planner, probably on a phone,
  and probably has no business seeing the journey map at all.
- Bundling them means the performer downloads/loads the whole authoring
  app to tap four buttons.
- Splitting later means moving auth, routing and the API client.

**Not a bug — a structural decision that gets expensive once APP-1 has
code in it.**

### 🟡 3. Publishing is one agent-day at a time

`plan_publication` is keyed per `timeline_id`, and a timeline is **one
agent, one day**. A team of five planned across a week is **25 separate
publish actions**. Bulk publish was deferred as a convenience; at 25
clicks it stops being a convenience.

Also unresolved, and worth checking before APP-1 relies on it: the table
is `appendOnly` with a unique `timeline_id`, which seems to mean **a day
can be published once and never re-published**. If a planner publishes
Monday and then genuinely needs to change it, it isn't clear what the
supported move is. I have not tested this — flagging it as a question,
not a defect.

### 🔴 4. There is no timezone anywhere in the system

Verified: **no `timezone` column on any table**. `planner_timeline.planned_date`
is a bare date supplied by the caller, and `activity_log.occurred_at` is
server time in milliseconds.

For one team in one city this is invisible. The moment there are two
timezones, "what's on my plate today?" has no defined answer — the
performer's device decides, the planner's device decided something else,
and the server is in UTC.

**Raised to 🔴 2026-10-15** after the founder confirmed this matters:
store Zulu, convert per user.

#### The storage is already correct — don't "fix" it

The founder's instinct (UTC in the database, convert on display) is right
**for instants**, and wrong for planned dates. Both already exist in the
schema, each with the right type, by luck rather than design:

| Field | Type today | Kind of time | Verdict |
|---|---|---|---|
| `activity_log.occurred_at` | `timestamp` (ms) | instant | ✅ UTC, convert on display |
| `work_task.started_at` / `completed_at` | `timestamp` | instant | ✅ same |
| `planner_timeline.planned_date` | `date` | calendar day | ✅ **leave as a bare date** |
| `planner_timeline.start_time` | `text` `"HH:MM"` | wall-clock | ✅ leave as text |

**Why `planned_date` must NOT become a UTC instant:** "Monday the 16th" in
Sydney is a different 24 hours than in LA. Stored as midnight Zulu, a
planner in LA sees their Monday render as Sunday 5pm. Keeping it a bare
date plus a wall-clock string also means **DST needs no handling at all** —
there is no instant to shift.

**So the data layer needs no migration.** What is missing is a reference
point: nowhere in the system says *whose clock* to convert to.

#### Level of effort

Three phases; they stack, and only the first is urgent.

| Phase | What it buys | LOE |
|---|---|---|
| **0 — build the seam** | APP-1 asks the server "what is today for me?" through one function instead of trusting the device. Function initially returns UTC. | **1–2 hrs** |
| **1 — account timezone** | One zone per company. Covers every single-location customer. Display conversion across both UIs. | **~½ day** |
| **2 — per-person timezone** | NY planner schedules for a Manila performer; each sees their own clock, planner sees both. | **~2 days** |

**Phase 0 is the one that matters now.** Without it, APP-1 hard-codes a
notion of "today" from the browser and every later phase is a rewrite of
the thing APP-1 is built around. With it, phases 1 and 2 are a change to
one function's body.

#### Two things that will shape the real cost

1. **`planner_agent` and `account` both carry `trim` text validators**, so
   adding a timezone column hits the documented `updateTableSchema`
   validator-drop bug. Per the standing workaround this becomes a **side
   table** (`planner_agent_timezone`) — plus, per the AUTH-1 lesson, **its
   own dedicated `GET` endpoint**, or the frontend silently never sees the
   value. That pattern is most of phase 2's two days; it is not the logic.
2. **Unverified:** whether XanoScript's `transform_timestamp` accepts IANA
   zone names (`"Asia/Manila"`) or only `"UTC"`. Every use in the repo so
   far passes `"UTC"`. If it does not support them, server-side "today for
   this person" has to be computed differently and phase 2 grows. **Worth a
   ten-minute scratch-function test before committing to the estimate.**

#### ✅ Decided 2026-10-15 (founder): the performer's timezone wins

Resolution order when they differ: **performer's zone → account's zone →
UTC.** The plan is about when that person actually works, so their clock
defines their day. A planner in another zone sees the performer's day
translated, not the other way round.

Phase 0 (the seam) lands inside APP-1. Phases 1 and 2 stay deferred.

### 🟡 5. "The user receives their tasks" — nothing pushes anything

Founder's description of execution is *"the user **receives** all their
tasks"*. Today the model is strictly pull: the app would ask the API
what's on today. There is no notification, email, or push anywhere in
the build order, and no device-token storage.

Not a gap in what was specified — a gap between the **spec and the
sentence the founder used to describe it**. Worth settling whether "MVP
performer app" means "opens the app and sees today" (pull, cheap) or
"gets told" (push, a whole piece of infrastructure).

### 🟡 6. `activity_log` grows forever, and the audit scans all of it

One row per tap, append-only, no retention. OBS-1's retention tiers are
deferred. `ops/audit_execution` currently reads every task, every job and
every log row, and runs one replay query **per task**.

Correct and fast today (7 tasks, 16 rows). It is O(tasks) queries per
nightly run, so it degrades smoothly rather than suddenly — but it is the
first thing that will need scoping to "open and recently-closed jobs"
rather than everything, exactly as the epic's own wording anticipated.

**No action needed yet.** Noting the trigger: when a nightly audit starts
taking minutes, this is why.

### 🟡 7. Five of six execution-layer epics shipped with no UI

PLAN-1, JOB-1, SCHED-1, LIVE-1 and LOG-1 are all backend-only. That was
the right call each time — the backend is the risky half and the specs
were detailed — but the debt is now concentrated: **templates, jobs,
scheduling and publishing have no screens at all**, and APP-1 only
addresses the performer's end.

Worth a deliberate decision about whether those get screens, or whether
the planner UI (item 1) is expected to absorb them when it gets wired.

---

## ✅ Fixed 2026-10-15 (APP-1): OBS-1's client-side event pipeline had never worked, for two independent reasons

Found while verifying APP-1 over a REAL browser against the real backend
— the first time any feature's `logEvent()` calls had been driven
through an actual page rather than a unit test or `runWorkspaceFunction`.
After every tap and every page load, `event_log` stayed completely
empty for `feature = "APP-1"`. Two separate, compounding defects, both
pre-existing and affecting every feature that uses `ops/logEvent.ts` —
not something APP-1 introduced:

**1. Wrong API group.** `xano.ts`'s `getOpsHealth`, `getOpsIssues`,
`getOpsBundle`, and `logEvent.ts`'s `defaultSend` all called
`xanoRequest('/ops/...')`, which targets the journey-map group
(`ER4MRRWZ`). The `/ops/*` endpoints live in their own group ("Ops",
canonical `-2MhtESP`, needing the `:v1` suffix). Confirmed live:
`ER4MRRWZ/ops/health` → 404; `-2MhtESP:v1/ops/health` → the app's own
friendly 403 (admin-only). **This means the Health page itself — the
founder's primary support tool — has never loaded real data in a real
browser**, independent of anything else. Fixed by adding an optional
`baseUrl` to `xanoRequest`'s options and a `getXanoOpsBaseUrl()`
constant (CLAUDE.md has the detail).

**2. The endpoint itself 403'd for everyone, admin or not.**
`apis/ops/1_ops_event_POST.xs` used `redis.ratelimit`/`redis.get`/
`redis.set` for its rate limit and de-dup window. All three are
rejected outright on this Xano plan (`"Not supported. Please upgrade
your Xano instance."`). So even pointed at the right URL, every call
still failed. Rewritten to do the same job — same codes, same windows
(20/min, 5s de-dup) — with a plain `db.query` against `event_log`
itself, no new infrastructure. Verified: first call `{accepted:true}`
and a row written; an identical call inside 5 seconds `{accepted:
false}` and no second row.

**Verified end to end through the real app, not a manual request**: a
real `Start`/`Reopen` tap and a real page load both produced correct
`event_log` rows with the right `feature`, `step`, `entity_id` and
`metadata`.

**Worth noting:** fix #2 is a judgment call, not purely mechanical —
it changes the rate-limit/de-dup mechanism from Redis to a DB query.
Made unilaterally because it restores already-documented, already-agreed
behaviour (same codes, same windows) rather than changing any product
decision, and because leaving the whole pipeline silently dead was
worse. Flagging it here rather than treating it as routine. The new
query is unindexed on `user_id` alone — fine at today's volume (the
table is pruned daily), worth an index if client-event volume grows
enough to matter.

---

## ✅ Fixed 2026-10-15: the Playwright harness's port mismatch — but existing specs have their own, separate issues

APP-1 and E2E-1 both substituted a real Chrome session for Playwright
(stronger anyway — every action verified by reading the database row
back), flagging the harness's reliability as unconfirmed rather than
chasing it mid-epic. Followed up afterward as its own small, bounded
fix, once the numbered build order was complete.

**Confirmed and fixed**: `playwright.config.ts`'s `webServer.port` and
`baseURL` were `5173` (Vite's historical default), but `package.json`'s
`dev` script hardcodes `--port=3000`. `webServer` was checking a port
the dev server never actually binds, so a clean `npx playwright test`
run could never reliably find or start it — the inconclusive run
during APP-1 was this, not a fluke. Pointed the config at 3000 (the
port the app actually runs on) rather than changing the dev script,
which other tooling may depend on.

**Verified the fix, not just the theory**: killed every stray dev
server, ran `e2e/cell-identifiers.spec.ts` from a genuinely cold start.
**The web server now starts and the test actually runs** — before the
fix, every spec would have failed before reaching a single assertion.

**What the fix does NOT cover**: the spec itself still fails, at a
DIFFERENT point — waiting for a chat-toggle button that never appears,
15s timeout. That's either stale test data, a missing auth/seed step,
or a selector that drifted from the real UI since the spec was
written. **Not diagnosed further** — that is a question about one
spec's own assumptions, not the harness, and chasing every existing
spec's content is a larger, separate task from fixing the one thing
that was silently breaking all of them equally.

**Needs**: before trusting ANY existing `.spec.ts` file as a completion
gate, give it the same treatment — run it cold, expect it may need its
own fix (auth setup, updated selectors) independent of this one.

---

## 🔴 Needs a decision: a codebase-wide null-vs-falsy sweep, found building VAR-1

`CLAUDE.md` now has the full detail: `== null`/`!= null` in XanoScript
is a PHP-style LOOSE comparison, so `0`, `""`, `false` and `[]` all
test equal to `null`. Confirmed directly with a scratch function.

**Why this is a 🔴 and not just a 🧠:** every epic built so far has used
`== null`/`!= null` as if it were a strict check. Most of the time this
is harmless by luck (timestamps are never really `0` in production,
most optional text/int inputs already have their own `""`/`0`-default
workaround for a different reason) — but nobody has ever swept the
codebase specifically LOOKING for the one combination that bites:
**a field whose real, legitimate value can be `0` and that is also
compared with a bare `== null`/`!= null`, with no `!= 0` alongside it.**

**Not done here, on purpose** — this is a cross-cutting audit, the same
shape as GOV-1's integrity sweep, not a VAR-1 fix. VAR-1's own use of
this comparison was checked by hand and is safe in production (every
timestamp it compares is a real epoch ms, never legitimately `0`), but
that was checked one function at a time, not swept.

**Recommendation:** a dedicated pass (Opus — this is exactly the kind
of subtle, easy-to-miss class of bug the model guidance table reserves
Opus for) that greps every `== null` / `!= null` in `apis/` and
`functions/`, and for each one asks "can the real column/variable here
legitimately be `0`, `""`, `false`, or `[]`, and is there already a
same-value guard next to it?" Likely candidates worth starting with:
anything comparing a `decimal` or `int` column directly (recall the
already-documented finding that an untouched decimal column defaults
to `0` in the database, not `null` — this is the SAME landmine from
the comparison side rather than the storage side).

---

## ✅ Fixed (security), both the code and the history: full user records were being logged, hashed secrets included

Found live during E2E-1's supportability drill, inspecting real
`event_log` rows for safety: `auth/login`, `auth/me`, `reset/magic-link-login`
and `reset/update_password` all passed the WHOLE `$user` record as event
metadata. That record carries the hashed password (`auth/login`, and
the password just set, `reset/update_password`) or the hashed
`password_reset.token` (`reset/magic-link-login`). `auth/me` fires on
every single page load — the highest-volume call in the app.

Same class of bug already fixed on signup (2026-10-14's "signup never
created an account" entry, in passing) — these four were missed at
the time. **Fixed immediately** (not just flagged) because it's the
identical, precedented, one-line change signup already got: `metadata`
is `{user_id, account_id}` only, everywhere. Verified live:
`auth/me` still works, and the resulting log row carries only the two
ids.

**✅ History cleaned 2026-10-16, on the founder's explicit go-ahead.**
Scrubbed `metadata` to `{user_id, account_id}` on every `event_log` row
from the four actions above whose metadata had more than those two
keys: **2,626 rows fixed**, out of 2,634 checked at the time (8 were
already clean).

**One real mistake caught and fixed before trusting it**: the first
attempt reported `scrubbed: 2626` and looked successful, but a
follow-up re-check found **every single row still fully exposed** —
`db.patch` on a `json` column turned out to MERGE the new object into
the old one rather than replacing it (now documented in `CLAUDE.md` as
its own critical finding), so "set metadata to `{user_id,
account_id}`" had silently added two keys without removing any of the
dangerous ones. Fixed by clearing the column to `null` first, then
setting the real value in a second patch — verified this time by
re-reading a specific previously-leaky row directly and confirming
zero rows still exceed two keys, not by trusting the function's own
counters a second time.

---

## 🔴 Missing capability, found building E2E-1: no way to add a map to an existing plan

US-E2E-1-02 needed two different work types in ONE plan instance.
PLAN-1's `template/{id}/instance` only accepts the maps listed on the
TEMPLATE **at the moment the instance is created** — `template/{id}`
PATCH's own header comment says so explicitly: "changes only what the
NEXT instance will be made from." There is no endpoint to add a map to
a workspace that already exists.

**Worked around for the test** by inserting a `planner_workspace_map`
row directly (scratch function, not a product fix) — this is exactly
the gap a real planner would hit the first time they wanted to add a
second work type to an already-running plan. **Recommend**: either a
small `POST workspace/{id}/map` endpoint, or make this one of PLN-9's
stories when that epic is scoped.

---

## 🧠 Worth knowing (E2E-1): an empty-string required field leaks a raw Xano message

`POST workspace/{id}/agent` with `name: ""` returned `"Missing param:
name"` — a raw framework message, not a VAL-1 catalog entry — even
though `name` is `required: true` and PLN-5 has its own friendly
`E-VAL-001` ("Give this person or agent a name.") for exactly this
case. Xano's own required-field check runs BEFORE the app's validation
code ever sees the request, for an empty string specifically (omitting
the key entirely, or sending whitespace, both reach the friendly
message — confirmed `"x".repeat(80)` correctly returns `E-VAL-002`).

**Narrow and minor** — found on one endpoint, during a drill, not swept
across every form. Worth a look whenever VAL-1's junk-corpus test is
run for real (US-E2E-1-11, not done this pass — see below).

---

## ✅ Verified during E2E-1: a fresh synthetic loop, map 178's data-safety rehearsal, tenancy

Full detail in `EPIC-E2E-1-end-to-end-validation.md`'s Test Results.
Worth summarizing the live state changes here specifically:

- **Left ON, deliberately**: `publish_gate` for account 6 (the
  session's standing test account). Reasoning: account 6 is disposable
  test data, not a customer; the flag only makes FUTURE publishes on
  it more correct (immutable versions), and turning it back off would
  remove a safety net from fixtures future sessions may reuse.
- **Map 178 (the real production fixture) was never written to.**
  Confirmed by re-fetching its snapshot after the rehearsal and
  comparing byte-for-byte against the one taken before touching
  anything — identical. All mutating calls (owner reassignment,
  duration fills, backfill) targeted only the clone, map 204.
- **New test data, safe to ignore or delete whenever**: journey maps
  202, 203 (E2E-1's synthetic "Receiving"/"Quality Check" SOPs, account
  6), clone 204 (account 2, `cloned_from_map_id: 178`), plan template 2
  and workspace 12 (account 6), agents 16 (linked to user 9).
- **New scratch functions, added to the held-for-deletion list below**:
  `claim_map` (149), `enable_flag` (150), `add_workspace_map` (151),
  `disable_flag` (152, created but never actually invoked — the
  decision above was to leave the flag on), `inspect_recent_events`
  (153).

**Caveat on the `xano-journey-map` MCP tool**: `create_journey_map` and
`clone_scenario` have no auth context, so every map they create lands
with `owner_user: 0, account_id: 0`. Both had to be patched by hand
afterward. Worth remembering for any future session using that tool —
it is not a bug in THIS project, just a gap between that tool and this
app's tenancy model.

---

## ✅ Fixed 2026-10-16 (PLN-9): the board endpoint hardcoded every timeline's status to "draft"

Same bug class LIVE-1 already found and fixed on two sibling endpoints
(539, 540): `workspace/{id}/board` (548, PLN-8 — "the whole plan in one
request") pushed `status: "draft"` as a literal, never `$tl.status`.
Never caught before because PLN-9 is the first real UI consumer of
this endpoint — a nightly audit or a functional test checking the
WRITE path wouldn't have noticed a READ-side hardcode like this.

**Verified it wasn't cosmetic**: the existing planner frontend already
has its own "(locked — timeline published)" UI logic gated on this
exact field. It was silently dead for every real published day until
now — confirmed by watching it correctly lock a real published
timeline's tasks the moment the fix went live.

Fixed: `status: $tl.status`, matching the already-established pattern.

---

## ✅ Started 2026-10-16: PLN-9 build, checkpoint 1 (login + real read)

Full detail in `EPIC-PLN-9-planner-frontend-wiring.md`'s Test Results.
Summarizing the state changes here:

- **New app at `webapp/emgram1010v1`**, copied from `planningFrontendv2`
  (`src/` confirmed byte-identical by diff at copy time — everything
  since is new). `planningFrontendv2` itself was NOT deleted or
  touched — left in place in case anything still needs cross-checking
  against it, pending a founder decision on whether to retire it once
  the new one is further along.
- **New test account** (user 10, its own account) created via real
  signup, used to prove the new app's login screen end to end.
- Confirmed **this app is a separate origin from `protype-2`** — no
  shared browser session, by construction, not a bug. One account
  logs into each separately.
- Writes are still local-only (same as the app's state before this
  epic) — only reading real data is wired so far. Not a regression;
  the deliberate next slice.

## ✅ 2026-10-15: PLN-9 build, checkpoint 2 — writes wired

- Agents (create/edit/visibility), tasks (create/edit/move/reorder),
  timelines (create/edit/move), and single-timeline publish all now
  hit the real backend from `webapp/emgram1010v1`, then refetch the
  whole board rather than hand-patching local state — see the epic's
  own Test Results for the full list and what's still deliberately
  unwired (deletes, reopen-to-draft, template/map stories).
- **New bug class, caught live before it shipped**: a `useState` hook
  declared AFTER a component's conditional early return
  (`if (!isOpen || !entity) return null`) is skipped on every render
  where that return fires, which changes the hook count between
  renders. React's own error is blunt ("Rendered more hooks than
  during the previous render") but `tsc` has no opinion on hook
  ordering at all, so this only surfaces by actually opening the
  component in a browser. Worth remembering for any other modal/panel
  component with an early return above its hooks.
- **This session had no working login for the app** (new conversation,
  no remembered password, and this app's login has no signup link).
  Recovered using the technique CLAUDE.md already documents for HTTP
  testing — `Getting Started Template/generate_magic_link` for a known
  test user's email, then a real POST to `reset/magic-link-login` —
  and wrote the resulting bearer token straight into the browser's
  `localStorage.authToken` via the browser tool's JS executor, rather
  than ever typing or storing a real password. Works for a UI session
  exactly as well as it works for a plain HTTP test.
- The browser automation tool's synthetic `left_click_drag` did not
  register with this app's drag-and-drop reordering — confirmed by
  elimination: the identical reorder, issued as a direct HTTP call to
  `timeline/{id}/reorder`, worked and the board correctly reflected it
  on the next load. Treat UI drag-and-drop as the one interaction this
  tool can't reliably drive; verify its backend call directly instead.

## ✅ 2026-10-16: PLN-9 build, checkpoint 3 — add-a-map, plan from template

- Two new, smoke-tested planner endpoints (569 GET / 570 POST
  `workspace/{id}/map`) close epic finding 5 — a plan already underway
  can now accept a second work type, which had no endpoint at all
  before this. Full details and the reasoning behind each design
  choice are in the endpoints' own header comments and the epic's
  Test Results.
- **Found a real, pre-existing platform bug, not introduced here**:
  `GET journey_map/search` (endpoint 210, a different/earlier epic)
  has 400'd on every call since the day it was created, because a
  same-group, same-verb dynamic route (`journey_map/{journey_map_id}`,
  built first) shadows it — the literal segment `search` gets parsed
  as an attempted id. Nothing about 210's own source is wrong, so the
  standing "diff local vs. live before pushing" rule would never have
  caught this. Full write-up and the general rule promoted to
  CLAUDE.md (routing collisions between a static and dynamic path in
  the same group). PLN-9 worked around it (plain `GET journey_map`,
  filtered client-side) rather than fixing 210, which still needs its
  own owner to resolve properly.
- "New Workspace" in the planner UI is now "New Plan from Template" —
  a real plan always comes from a template now (window, maps, start
  time all derive from one), matching PLAN-1's model instead of the
  old bare-name placeholder.

---

## How to use this file

When picking up any of the 🔴/🟡 items: read the linked epic file in
`product/stories/phase-4/`, make the fix, then **move the entry here to
✅ with a one-line note on what changed and when** — don't delete it,
so there's a record of what was wrong and why.
