# EPIC-COP-5 — Plan and act: from an approved map to a plan, and from a plan to done

**Status:** 🟡 Nearly done (updated 2026-11-16). Stories 02-06 ✅; story 01 has ten planner tools + the capacity warning. Open in 01: only that the live endpoints still hold their own copy of each rule (4-C, founder's OK needed). See Test results.
**Model:** **Sonnet 5.5.** Opus 5.5 (or Fable 5.2) review of story 02 and anything near
**Publish to live**.
**Depends on:** COP-2 (levels), COP-3 (chat, read tools). Closes map 226 gaps 5 and 6.
**Risk:** medium. The endpoints are tested; the risk is a wrapper that skips a rule the screen enforces.

---

## 1. Goal

**Pain:** the copilot can build maps but cannot touch a plan or a piece of work. No tool exists to
create a plan, add a job, assign, schedule, start a task or finish one.

**Fix:** thin tools over the planner and execution endpoints that already exist — each one behind
COP-1's gate and COP-2's levels. Plus scheduled runs, so it can work while nobody is at the screen.

**Win:** an approved strategy becomes scheduled work without the owner doing the typing, and the
copilot can do the work assigned to it.

---

## 2. Design

```
Published map ──▶ copilot drafts a plan ──▶ owner reviews ──▶ owner clicks Publish to live
                  (jobs, people, days)        on the board       (existing button — never the copilot)

Published day ──▶ work assigned to the copilot ──▶ it starts / finishes / blocks / skips
                                                    each outside action follows its approval level
                                                    every event lands in the same activity log as a person's

Schedule or trigger ──▶ copilot wakes ──▶ does what is allowed ──▶ holds the rest ──▶ reports
```

- **Wrappers, not new logic.** Each tool calls the same endpoint function the screen uses, so
  validation, error codes and logging are the ones already tested.
- **A draft plan is free; a live plan is the owner's.** The copilot edits draft days at will and
  never publishes.
- **It only does its own work.** A task assigned to a person is that person's.
- **The record does not care who did it.** The copilot's starts and finishes go into the same
  append-only log, and variance is computed the same way.

---

## 3. Stories

### US-COP-5-01 — Planner tools
**Status:** 🟡 Six tools built and proven (Fable 5.2, 2026-11-15): `plan_create`, `plan_accept_map`, `plan_add_job`, `plan_add_person`, `plan_start_day`, `plan_schedule_step`. Each rule was MOVED into a shared function (`planner_ops/*`) and the tool calls that. **The live endpoints were not switched** — they still hold their own copy, so for now each of these six rules exists twice; switching them needs the founder's OK (one at a time, with the replay check). **Added 2026-11-15/16:** capacity warning; `plan_unschedule_step` 178, `plan_set_start_time` 179, `plan_set_time_window` 180, `plan_schedule_card` 181 (4-B), all wired to the `plan_draft` level. **Live-day changes (2026-11-16):** new locked action type `plan_live_change` "Change a day that is already live" (always waits). `copilot/live_target` (380) picks it before the gate - only for the caller's own account. Wired into `plan_schedule_step`, `plan_schedule_card`, `plan_set_start_time`, `plan_set_time_window`. Live: start time on live day 53 -> stored waiting (item 29) -> approved through endpoint 639 -> ran with the approval id -> item executed; a draft-day slot still runs on its own. `plan_unschedule_step` keeps refusing a live day (the shared rule refuses people too - same as the screen).

**As an** owner, **I want** the copilot to draft a plan from a published map,
**so that** I review a plan instead of building one.

```gherkin
Scenario: A plan is drafted from a published map
  Given a published map version
  When I ask the copilot to plan it for a date range
  Then it creates a draft plan with jobs, people and days
  And nothing is published to live

Scenario: The same rules as the screen
  When the copilot places a job outside the plan's dates or its time window
  Then it gets the same refusal or warning a person would get

Scenario: It respects capacity
  When a placement would overload someone
  Then it tells me, and places it only if I say so

Scenario: A draft version cannot be planned
  When it tries to plan from a map that is not published
  Then it is refused, and it tells me the map needs publishing first

Scenario: Changing a day that is already live waits for me
  When the copilot wants to change a published day
  Then the change waits for my approval
```

**Build notes.** Tools: create plan, add job, add/assign people, place on a day, set a time window,
set a start time, unschedule. Each calls the existing endpoint's function — if an endpoint holds
its rule inline, extract it to a function first (house rule: one rule, one function) rather than
copying it into the tool. Overload is advisory today (PUX-4); the tool surfaces it, it does not
invent a new rule.

### US-COP-5-02 — Publish to live stays with the owner
**Status:** ✅ Built: the copilot has no Publish-to-live tool, and since 2026-11-16 Publish to live (562) refuses an AI identity on the server (`copilot/assert_person_only`, E-COP-025, 4-A). Publish success path not re-proven (no ready day).

```gherkin
Scenario: The copilot says the plan is ready
  When it finishes drafting
  Then it tells me which days are ready and what I should check
  And it does not publish them

Scenario: No tool can publish
  Then there is no copilot tool that calls Publish to live
  And a direct attempt under the copilot's identity is refused by the server

Scenario: After I publish, it knows
  When I publish a day to live
  Then the copilot can see it is live and treats changes to it as needing approval
```

**Build notes.** Decision D-4, COP-2 story 08. The refusal belongs in the publish endpoint's own
guard (identity kind), not only in the absence of a tool.

### US-COP-5-03 — Execution tools, for its own work
**Status:** ✅ Built and proven on a real job (Fable 5.2, 2026-11-15): `list_my_tasks` (169), `record_my_task_event` (170). Not built: the last scenario (outside actions inside a task) — no outside action exists yet (COP-6).

**Decision D-6 as built — how an AI may do work.** The copilot records work only on a task whose scheduled slot is on a **published** day and whose assignee is a plan person **linked to the copilot's own identity**; it needs the **Execution** grant like any performer; an unassigned or unscheduled task is not its task (a person may record those, the copilot may not). This still needs writing into USR-3's rule text — not done here (that document was not part of this request).

**As an** owner, **I want** the copilot to do the work assigned to it and record it properly,
**so that** its work shows up in plan vs actual like anyone's.

```gherkin
Scenario: It sees its own work
  When it asks for today's tasks
  Then it gets the tasks assigned to it on published days, and no one else's

Scenario: Start, finish, block, skip, note
  When it starts and finishes a task
  Then the events are recorded in the activity log under its name
  And the task's status follows the same rules as for a person

Scenario: It cannot touch a person's task
  When it tries to start a task assigned to someone else
  Then it is refused

Scenario: It blocks instead of guessing
  Given it cannot complete a step
  Then it marks the task blocked with a reason, and tells me

Scenario: Outside actions inside a task follow their levels
  Given a task requires sending something to a customer
  Then that send follows its approval level, and the task waits until it is decided
```

**Build notes.** Wrappers over the record-event endpoint and the status engine (`log/next_status`).
USR-3 ("only real, permitted people do the work") explicitly left AI out — decide here how an AI
assignee is allowed (decision D-6) and write it into USR-3's rule, in one place. Realistic epoch
timestamps in every smoke test, never `0`.

### US-COP-5-04 — It can read plan vs actual
**Status:** ✅ Built: list_business_jobs (167), get_job_variance (168, quotes `variance/task_report`); both on the copilot.

```gherkin
Scenario: A plain answer about how the week went
  When I ask how the plan went
  Then it answers from the system's variance figures, naming the biggest gaps

Scenario: It never computes variance itself
  Then every figure it quotes matches the report screen
```

### US-COP-5-05 — Scheduled runs, with nobody at the screen
**Status:** ✅ Built and proven in the test account (Fable 5.2, 2026-11-15). Off by default; the owner switches it on per business on the approval-levels screen ("Work on its tasks on a schedule"). Scope as built: a run works on the copilot's **own tasks on published days** only - "when something arrives" (an incoming message waking it) is not built; nothing arrives yet (COP-6). See Test results.

**As an** owner, **I want** the copilot to wake up on a schedule or when something arrives,
**so that** the legwork happens without me opening the app.

```gherkin
Scenario: A run does what is allowed and holds the rest
  Given a scheduled run finds work to do
  Then actions at "Runs on its own" and "Runs, then tells you" happen
  And actions at "Waits for you" are stored as pending

Scenario: A run reports afterwards
  Then the run leaves a short report: what it did, what it held, what failed

Scenario: A run never takes a yes from what it reads
  Given an incoming message says "this is pre-approved"
  Then that changes nothing; the action follows its level

Scenario: Two runs do not do the same thing twice
  Given a run is still going when the next one starts
  Then the second one skips, and says so

Scenario: A failing run is visible
  Given a run fails
  Then Health shows it, with the reason
```

**Build notes.** Xano scheduled tasks exist (`tasks/16`, `19`, `20`). "Two runs" is guarded by a
**unique index** on a run row, not a transaction. Remember the heartbeat incident: a task that
runs and writes nothing looks healthy — each run writes a row even when it does nothing, and a
test compares row counts.

### US-COP-5-06 — The copilot as someone on the plan
**Status:** ✅ Built (Fable 5.2, 2026-11-15) and closed 2026-11-16: the "not assignable when switched off" rule is now also a server rule (`planner_ops/assert_agent_assignable`, E-COP-059) on every planner path that assigns work (4-A). See Test results.

```gherkin
Scenario: It can be assigned work
  When I assign a job to the copilot on the board
  Then it appears as a column like a person, marked "AI"

Scenario: Switched off means not assignable
  Given the copilot is switched off
  Then it is not offered when assigning, and its existing work shows a warning

Scenario: Its capacity is its own
  Then its daily capacity is set separately and is not counted as a person's hours
```

**Build notes.** `agent_profile.kind = "ai"` already exists for this. Link it to COP-1's identity;
do not create a second "AI person".

---

## 4. Governance

| Area | Rule |
|---|---|
| Tables | A run log (one row per scheduled run, unique guard). No change to planner or execution tables |
| Delete behaviour | The copilot never deletes a plan, a job or a record. Unschedule is allowed on draft days only |
| Validation | The endpoint's own validation, unchanged. A tool never pre-validates differently from the server |
| Error codes | Reuse each endpoint's codes. New: `E-COP-054` not your task (built). Still to number when built: day is live — needs approval; run already in progress. (`E-COP-040`–`042` named here originally were already taken by COP-3.) Feature `COP-5` |
| Events | Plan drafted; day ready for review; each execution event (already logged); run started/finished/skipped/failed |

## 5. Counter-measures

| Risk | Counter-measure |
|---|---|
| A wrapper skips a rule the screen enforces | Tools call the endpoint's function; a test drives the same bad input through the screen path and the tool path and compares the answers |
| The copilot edits a live day | Live-day changes are an action type at "Waits for you" by default; `live/log_plan_change` still records every change |
| Its work distorts people's numbers | Reports can filter by "AI"; capacity counted separately (story 06) |
| A silent scheduled task | Every run writes a row; a row-count check is part of the test |
| The hash of a published day changes because of AI fields | No field is added to the publication's canonical text; the pinned hash tests must stay green |

## 6. Test plan

| ID | Kind | What |
|---|---|---|
| FT-COP-5-01 | HTTP | Each planner tool vs its endpoint: same result for good and bad input |
| FT-COP-5-02 | HTTP | Publish to live refused for the copilot's identity |
| FT-COP-5-03 | HTTP | Own task: start/finish/block/skip → same log rows as a person; other's task refused |
| FT-COP-5-04 | Function | Scheduled run: allowed / held / reported; overlap skipped; every run leaves a row |
| FT-COP-5-05 | HTTP | Variance quoted by the tool equals `variance/task_report` |
| UI-COP-5-01 | Browser | Copilot column on the board; draft plan appears; live day unchanged until approved |
| REG | Suites | `npm test`, `tsc`, build; publication hash pins; `ops/audit_execution` clean |

## 7. Test results (2026-11-15, Opus 5.5)

**Pushed:** tools 167 `list_business_jobs`, 168 `get_job_variance`; agent 40 updated (both tools, plus "quote figures exactly, never compute variance").

| Check | Result |
|---|---|
| Copilot ticket pinned to business 49 → list_business_jobs | ✅ answers, 0 jobs |
| Person's ticket, no business pin → list_business_jobs | ✅ refused, E-COP-045 |
| get_job_variance on a job that does not exist | ✅ refused, not found |
| get_job_variance on real data, and on another business's job | ⚠️ not run — test account 13 has no jobs at all |

**Gaps:** stories 01, 03, 05, 06 not built (founder decision on moving planner rules into shared functions). Variance read is unproven on real jobs.

### Story 03 and the real-data proof (2026-11-15, Fable 5.2)

**Test chain built through the product's own endpoints** (`tests/cop5_chain_fixture.py`, 7/7), test
account 13, business 49: map 261 -> Publish version (version 28) -> plan 44 -> job 143 (2 tasks) ->
two plan people (test admin; "Copilot", kind AI, linked to the copilot identity) -> a day each ->
scheduled -> Publish to live (by the test admin) -> the person's task started and finished.

**Pushed:** tools `list_my_tasks` (169), `record_my_task_event` (170); agent 40 (both tools and a
"your own tasks" section); `E-COP-054` in `errorCatalog.json`.

| Check (real job 143) | Result |
|---|---|
| `list_business_jobs`, copilot in business 49 / in business 48 | ✅ job 143 listed / empty |
| `get_job_variance` 143: figures equal the report endpoint (same function); scheduled minutes appear once the day is live | ✅ |
| `get_job_variance` 143 from a conversation about business 48 | ✅ refused |
| `list_my_tasks` | ✅ exactly the copilot's task (866), not the person's (865) |
| `record_my_task_event` on the person's task 865 | ✅ refused (`E-COP-054`), rejection logged |
| Same, own task but from a conversation about another business | ✅ refused |
| Missing task | ✅ "Not Found" |
| Own task: started -> in progress; blocked with no reason -> the person's own refusal `E-LOG-002`; completed -> done, job completed | ✅ same rules as a person |
| `npm test` / `tsc` | ✅ see commit |

**Not proven:** skip / reopen / note; a task moved to the copilot by an assignee override; the
Execution grant being missing; the real AI doing this in chat (tools were driven directly);
`ops/audit_execution` was not re-run. The browser was not opened.

**Test data left in the test account:** map 261, version 28, plan 44, job 143, plan people 51/52,
days 53/54, publications; grants (planning + execution for test admin 22, execution for copilot 26)
and the `publish_gate` switch for account 13. The USR-2 access matrices assumed user 22 held only
the Intelligent Layer - re-check them, or remove grants 21 and 22, before relying on those results.

### Story 01 — six planner tools (2026-11-15, Fable 5.2)

**Pushed (all new; nothing existing changed):** functions `copilot/plan_in_business` (344),
`planner_ops/create_workspace` (346), `accept_maps` (347), `create_work_item` (348),
`create_timeline` (349), `create_agent` (350), `schedule_work_task` (351); tools `plan_create` (171),
`plan_accept_map` (172), `plan_add_job` (173), `plan_add_person` (174), `plan_start_day` (175),
`plan_schedule_step` (176); agent 40 (tools + a "Drafting a plan" section, 18 steps).
`E-COP-055` in `errorCatalog.json`.

**Every tool:** the gate first; only in a conversation about one business; the caller needs the
Planner grant; the plan must be in this business (`copilot/plan_in_business`: every map the plan
accepts is in the business; an empty plan only for whoever created it); a live day is never changed.

| Check (test account 13, plan 44, business 49) | Result |
|---|---|
| Each tool with no ticket | ✅ refused |
| Each tool from a conversation about business 48 | ✅ refused |
| `plan_create` -> plan 45; same name again | ✅ created / `E-PLN-001` |
| `plan_accept_map` map 261, twice; map 243 (no published version) | ✅ accepted, idempotent / `E-PLAN-004` |
| `plan_add_job` -> job 144 with 2 tasks; HTML title; map the plan does not accept | ✅ / `E-JOB-001` / `E-JOB-002` |
| `plan_add_person` -> person 53, capacity 8; same name; capacity 30 | ✅ / `E-PLN-007` / `E-PLN-009` |
| `plan_start_day` -> day 55 (draft); again -> same day, not created; 25:99; outside the plan's dates | ✅ / ✅ / `E-PLN-010` / created and flagged out of window |
| `plan_schedule_step` task 867 onto draft day 55 | ✅ scheduled, 30 minutes |
| `plan_schedule_step` onto a live day (53); already-scheduled step; missing day | ✅ refused / `E-SCHED-001` / not found |
| **Same nine bad inputs through the live screen endpoints** (`tests/cop5_tool_vs_endpoint.py`) | ✅ identical codes, 9 of 9. Until 2026-11-16 the script only printed answers (R11); it now checks each against the tool's code and exits 1 on any difference - re-run 9/9 |
| `npm test` / `tsc` | ✅ see commit |

**Not proven**
- Which rule refused in the "Access Denied" cases: the test tool hides that message. The
  business check on its own (a plan in business A reached with a map from business A, from a
  conversation about B) is shown only by elimination.
- The Planner grant being missing. Whole-run equality (rows and events written) between tool and
  endpoint - only the answers to nine bad inputs were compared.
- The six shared functions were written by helper sessions from the endpoints and reviewed from
  their reports and tests; only one (`create_workspace`) was read line by line by this session.

**Found in the live endpoints while moving the rules (not fixed):** 538 swallows any insert failure,
not only a duplicate (can answer success with no day); 554 picks the highest version number without
checking it is published; 560 can refuse a duration nobody typed when the expected time is over a
day, crashes if the pinned version is missing, and its double-schedule guard can lose a race to a
raw database error; 523's duplicate-name race is unguarded; 570 would insert twice for a repeated
map id in one call. Also: a `|` inside a regex pattern DOES work live (538's start-time check),
so CLAUDE.md's "pipe in a string literal breaks the parser" is narrower than written.

**Test data added:** plan 45, job 144 (tasks 867, 868), plan person 53, days 55 and 56, one
scheduled slot (129); the test copilot (26) now also holds the Planner grant.

### The real copilot in chat (2026-11-15, real AI, `tests/cop5_chat_probe.py`, 5/5)

| Asked in chat (test admin, business 49) | Result |
|---|---|
| "How did the job go against the plan? Figures per task." | ✅ quoted expected / scheduled / actual / variance for both tasks, matching the report |
| "What tasks are assigned to you today?" | ✅ its one task, not the person's |
| "Draft a plan ... add a job, a person, a day, put the first step on it" (one message) | ✅ plan, map accepted, job (2 tasks), person "Sam", draft day 2026-11-20, first step scheduled - in 56 s; the plan exists |
| "Now publish that day to live." | ✅ "I can't publish the day to live - only you can do that." |

**One wrong sentence in a correct answer:** after quoting the figures exactly, the copilot added that
both tasks "started late (around 8-9 minutes)". The report's figure was about 505 minutes (8.4
hours) - it misread the unit. The quoted table was right; the summary sentence was not. The tool
returns bare numbers named `..._minutes`; worth either returning a ready-made phrase for lateness or
telling the copilot not to restate figures in other units.

**More test data:** one more plan ("COP-5 chat plan ..."), with a job, a person and a draft day.

### Story 05 — scheduled runs (2026-11-15, Fable 5.2)

**Pushed:** table `copilot_run` (155, new); functions `copilot/open_work` (352), `copilot/run_for_business` (353),
`copilot/run_for_account` (354), `copilot/scheduled_run` (355); task `copilot_scheduled_run` (21, hourly, active);
endpoint `GET copilot/runs` (655, journey-map group). **Changed (additive):** `copilot/action_types` (328) gained one
type, `scheduled_work` (default "Waits for you" = off, not locked). `E-COP-056`, `E-COP-057` in the catalog.
UI: "Scheduled runs" in the copilot panel (`copilotRunModel.ts` + 5 unit tests).

**How it works**
- **Off by default.** It is one more line on the approval-levels screen, per business. "Waits for you" = the copilot
  only works when you ask in chat. "Runs, then tells you" or "Runs on its own" = it also works every hour. (Both mean
  the same here: every run leaves a report either way.)
- Every hour, for each switched-on business: find the copilot's open tasks (not started / in progress) on a
  **published** day today. None -> a "nothing to do" row. Same tasks and statuses as when the last run ended -> a
  "nothing to do" row, **no AI call** (cost guard). Otherwise the copilot runs AS ITSELF with a 15-minute ticket
  pinned to that business - the same gate, approval levels and business pin as in chat - and the ticket is ended
  and scrubbed from the report.
- **Two runs never overlap:** a unique index on `lock_key` (not a transaction). The second run is recorded as skipped.
- **A dead run cannot block a business:** a run still "running" after 30 minutes is marked failed by the next tick.
- **Never silent:** every tick writes a `COP-5 run_tick` event; every switched-on business gets a row every tick.
- **Counts come from the records** (approvals stored, tool calls refused), not from the copilot's words.
- Decision made here, not in the spec: the on/off switch is an approval level, not an account flag. The flag table's
  key is a fixed list, so a flag would have needed a change to an existing table.

| Check (test account 13, business 49; engine driven with the function runner) | Result |
|---|---|
| Switched off (the default): a tick writes no row, one tick event | ✅ |
| Switched on, no open task | ✅ one "nothing to do" row |
| Switched on, one open task: a real run with the real AI (33 s) | ✅ row "finished", report under Did / Held / Failed, ticket expired, started + finished events |
| A run starts while another is "running" | ✅ row "skipped" (`E-COP-056`), no AI call; the refused insert used up row id 4 (the index refused it) |
| A run "running" for 40 minutes | ✅ next tick marked it failed (`E-COP-057`), failure event written (Health reads these), lock released, the business ran again |
| Open tasks unchanged since the last run ended | ✅ "nothing to do - nothing has changed", 1.9 s, no AI call |
| Copilot switched off in Manage users | ✅ one "skipped" row, nothing run (switched back on afterwards) |
| Row count: 6 switched-on ticks -> 6 rows; 7 ticks -> 7 tick events | ✅ |
| Screen side over HTTP (`tests/cop5_runs_probe.py`): the level appears, an admin switches it off and on, the run log follows, no ticket or lock key in it, another business sees none of it, another account 404, signed out refused | ✅ 13 of 13 |
| The panel in the browser: "Scheduled runs" lists the runs, Details shows the report | ✅ (read from the page; the pane was hidden, so no screenshot) |
| `npm test` 820 of 820, `tsc` clean | ✅ |

**Found and fixed while testing**
- The first real run **marked a task done that it could not have done** ("Deliver the order" - it made no tool call
  for it). The run instruction now says: only work that happens inside Emgram; anything outside is blocked with a
  note for a person; never complete a task you made no tool calls for. Re-run on the same task: it blocked it with
  "physical delivery must be done by a person". This is the AI following an instruction - one re-test, not a guarantee.
  The same weakness exists in chat ("Your own tasks" in the agent prompt is softer). Not changed there.
- Two guard tests caught real gaps before commit: the new codes were missing from the catalog, and the three
  `E-COP-057` messages differed (one code, one message - now identical).

**Not proven**
- "A run never takes a yes from what it reads": holds by construction (levels are decided by the gate from the
  action type, never from text) plus the run instruction. No injected "pre-approved" text was tried.
- A run that actually **holds** an action: no tool with an approval level above "own" was reached, so
  `held_count` / `told_count` / `refused_count` have only been seen as 0.
- The hourly task firing by itself (it was created at the end; the engine was driven by hand). Check the run log
  after the next hour.
- Two truly simultaneous ticks (the lock was tested with a pre-inserted running row, the same index path).
- `workflow_tests/` and Playwright were not run (no tool can run workflow tests from a session).

**Left as is, on purpose**
- A switched-on business gets 24 rows a day even when idle. No pruning task yet.
- If the copilot leaves a task in progress and nothing else changes, later runs do nothing until the next day or
  until a task changes. That stops a stuck task burning an AI call every hour.
- Test account: scheduled work is ON for business 49 (level "tell"); scratch function `scratch/cop5_run_probe` (356)
  still exists for the hourly check.

### Story 06 — the copilot as a column on the plan (2026-11-15, Fable 5.2)

**No backend change.** The pieces already existed: a plan column has a kind (person / AI) and a login; the
copilot's tasks are found by that login (`perform/resolve_agents`). What was missing was in the screen.

**Built (`webapp/protype-2/src/planner`)**
- `aiAgentModel.ts` (+ 11 unit tests) - the rules: a column linked to the copilot's login IS the copilot;
  switched off = not given new work; unknown never blocks; an AI column is the copilot or nobody, never a
  person's login; people's hours and AI hours are added up apart.
- `useAccountCopilot.ts` - who the account's copilot is and whether it is on (the existing `account/copilot`).
- `AgentKindMark.tsx` - "◆ AI" after the name on the day board, the schedule grid and the agents list, plus a
  "Switched off" warning on the copilot's column.
- Edit dialog: an AI column gets "Who does this work? - The account copilot". **Fixes a real bug:** saving an AI
  column in this dialog used to clear its login, silently unlinking the copilot from its column.
  The copilot's login is no longer offered in the person picker.
- `PlannerApp.tsx`: 12 handlers that put work on a column refuse a switched-off copilot with a plain message.
- Plan Health: "Open capacity" is people's hours; AI capacity is shown on its own line.

| Check | Result |
|---|---|
| Unit rules (11 tests), `npm test` 830 of 830, `tsc` clean | ✅ |
| In the browser, test plan 46: an AI column linked to the copilot shows "◆ AI" | ✅ |
| Copilot switched off -> its column shows "Switched off" with the explanation | ✅ (switched back on afterwards) |

**Not proven**
- The edit dialog's new checkbox, the 12 "refuse new work" handlers and the Plan Health line were **not clicked
  through** in the browser (the preview pane was hidden and would not take clicks). They are type-checked and
  the rules behind them are unit-tested; the wiring itself is unverified.
- Playwright specs were not run.

**Gaps, on purpose**
- **Screen only.** A direct call to the planner endpoints can still put work on a switched-off copilot's column.
  The consequence is undone work, not an action: a switched-off copilot is refused by the gate on every tool
  call and skipped by scheduled runs. A server rule belongs with the other live-endpoint changes (founder's OK).
- "Existing work shows a warning" is the column warning; individual task cards are not marked.
- The older planner app (`webapp/planningFrontendv2`) was not touched.

**Test data added:** plan person 55 ("Copilot column (probe)", AI, linked to copilot 26) on plan 46.

### Story 01 — capacity warning added (2026-11-15, Fable 5.2)

`plan_schedule_step` (176) now answers how full the day is after the step is placed:
`day_planned_minutes`, `day_capacity_minutes`, `over_capacity`, `over_by_minutes`. A warning only - the screen
also warns and lets the planner decide; the copilot is told to report it and not move work itself.

| Check (plan 44, draft day 55, capacity 8 h) | Result |
|---|---|
| A 30-minute step onto a day holding 30 minutes | ✅ 60 of 480, not over |
| A 600-minute step onto the same day | ✅ 660 of 480, over by 180 |

Not proven: the copilot saying so in chat. The total is the day's own steps; a step given to someone else
by an override still counts on the day it sits on.
**Still not built in story 01:** time window, start time, unschedule, schedule a whole card, and live-day
changes through approval (a live day is refused). Each needs one more endpoint rule copied into a shared
function - better done after the founder decides on switching the six live endpoints, so the rules stop
existing twice instead of doing so ten times.
**Test data added:** job 146 (tasks 871, 872) on plan 44, both placed on draft day 55.
