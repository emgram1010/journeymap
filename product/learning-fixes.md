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

## 🔴 Needs your approval: the planner's delete paths are written but not pushed

Two of them now, and the same question blocks both. CLAUDE.md says to
ask before any delete, and the session's permission layer independently
refused the pushes.

- **Ready for review:** `functions/planner/delete_workspace_cascade.xs`
  (children first, one `db.transaction`, counts taken before deleting)
  and `functions/planner/delete_model_guard.xs` (refuses while any
  agent still references the model, and names them).
- **Blocks:** FT-PLN-3-07/08/09 and US-PLN-3-04/05; FT-PLN-4-08/09 and
  US-PLN-4-05.
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

## How to use this file

When picking up any of the 🔴/🟡 items: read the linked epic file in
`product/stories/phase-4/`, make the fix, then **move the entry here to
✅ with a one-line note on what changed and when** — don't delete it,
so there's a record of what was wrong and why.
