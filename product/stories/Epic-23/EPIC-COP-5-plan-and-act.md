# EPIC-COP-5 — Plan and act: from an approved map to a plan, and from a plan to done

**Status:** 🟡 Partly built (2026-11-15) — stories 03 and 04 built and proven on a real job. Stories 01, 05, 06 not built; 02 holds by design (no publish tool exists). See Test results.
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
**Status:** ⏸ Waiting on the founder. The planner's rules live inside live endpoints (538, 542, 545, 560, 583, 613, 617, 562, 535); tools need those rules moved into shared functions first — a change to code the live planner runs on.

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
**Status:** ✅ Holds today by construction: the copilot has no Publish-to-live tool and no login. The endpoint-level guard is deferred until story 01 adds plan tools. **Opus review:** pending.

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
**Status:** ⏸ Waits for story 01.

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
**Status:** ⏸ Waits for story 01.

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
