# Epic-29 — START HERE. Repeat a plan, and assign work to the right available person

**Status (2026-11-25):** 📋 Docs only. Nothing is built. No code, no Xano change.
**Raised by:** founder, 2026-11-25.
**Written by:** Fable 5.2, same day, against the repo files. **Live Xano was not compared.**
Every epic starts with a read-only story (`-00-`) that does that before anything is built.

---

## 1. The two initiatives

| # | Initiative | In one line |
|---|---|---|
| A | **Repeat a plan** | A planner builds one period (a week, for example) once, then repeats it for the next period with one action. |
| B | **Right person for the work** | A step can say what it needs. A person can say what they hold and when they work. The system suggests who fits, refuses a hard mismatch, and never gives work to someone who is off that day. |

**Priority (founder, 2026-11-25): A first, then B.** Repeating is felt every week by every planner,
and it is half-built. B needs three new ideas (what a step needs, what a person holds, when a
person works) before it can match anything.

## 2. What is in this folder

| Folder | Epic | ID | Size | Model |
|---|---|---|---|---|
| `E1-repeat-a-plan/` | Repeat a plan for the next period | REPEAT-1 | L | Sonnet 5.5 for 00–02, 05–07 · **Opus 5.5** for 03 and 04 · then an Opus review |
| `E2-requirements-and-qualifications/` | What a step needs, and who holds it | REQ-1 | L | Sonnet 5.5 · **Opus 5.5** for 05 (it touches Publish version) |
| `E3-availability/` | Working days and time off | AVAIL-1 | M | Sonnet 5.5 |
| `E4-matching/` | Suggest, refuse, and recheck at Publish to live | MATCH-1 | L | **Opus 5.5**, then an Opus review (a guard on every path that assigns work) |

Each folder holds `epic.md` and one file per story (`US-<ID>-<nn>-<name>.md`).

**Build order:** E1 → E2 → E3 → E4. E3 may run alongside E2 (they share no tables).
E1 leaves one hook open on purpose (story 04, "drop anyone unavailable"); E4 story 03 closes it.

## 3. What reading the repo found (read before building)

| # | Finding | Where it is handled |
|---|---|---|
| F-1 | **A plan template already repeats the shape of a plan, not its content.** `POST template/{id}/instance` copies the window length, the accepted maps and the roster. It copies no days, no jobs, no order and no assignments. | REPEAT-1, all stories |
| F-2 | **A job is pinned to one published map version.** Copying a job row as-is would pin next week's work to last week's definition for ever. A repeated job must be created fresh, pinned to the map's **current** published version. | REPEAT-1 story 03 |
| F-3 | **Some jobs must never be repeated.** A job that came from an outside order (`work_item_origin`), a child job spawned by an exception, and a cancelled job are one-off facts, not a pattern. | REPEAT-1 stories 01, 03, decision D-5 |
| F-4 | **A person on a plan has no link back to their lasting profile.** `planner_agent` is created fresh per plan and has no `agent_profile_id`. A person can be joined through `user_id`; an AI profile with no login, or a person added by hand with no login, cannot. Qualifications and availability live on the lasting profile, so this link is needed first. | REQ-1 story 03 |
| F-5 | **Nothing stores what a step needs or what a person holds.** `agent_capability` is the AI tool registry. `copilot_skill` is the copilot's "how I work" library. Neither is this, and their names must not be reused. | REQ-1 |
| F-6 | **Nothing stores availability.** A person has daily hours (`daily_capacity_hours`). Only the AI tools `plan_schedule_step` and `plan_schedule_card` read it, to **warn** when a day is over (they treat 0 as 8). No endpoint refuses an over-full day, which matches D-9. There are no working days and no time off. *(Corrected 2026-11-25 against live.)* | AVAIL-1 |
| F-7 | **"Eligible" is taken.** `agent_profile.is_eligible` means "may be put on a roster". This folder says **holds**, **available** and **fits**; never "eligible". | All |
| F-8 | **Many places put work, or a day, on a person — but one shared check already exists.** `planner_ops/assert_agent_assignable` is documented as "the one server check for may new work land on this plan column" and is called by 541, 542, 543, 545, 583, `schedule_work_task`, `schedule_card` and `create_timeline`. Matching extends **that** check (adding the date and the steps); it does not add a guard to each caller. Paths that put work on a person: 541 (change a day's person or date), 542 (create a slot), 543 (place or move a slot), 545 (change a slot's person), 560 and `schedule_work_task` (schedule a step), 583 and `schedule_card` (schedule a card), `live_add_attempt` (reached by 449 `add_job_to_live_day` and 450 `orders/place_live`), AI tools `plan_schedule_step`, `plan_schedule_card`. Paths that put a **day** on a person (availability matters): 538 and `create_timeline`, AI tool `plan_start_day`. Other: 536 (changing a column's `user_id` re-points everything on it to another login), 551 (creates people, no work), `planner/place_task` (checks nothing itself; 543 checks first). **Not a path:** 544 reorder refuses anything but a reorder of the same day's slots. 583 keeps its own copy of the card rule instead of calling `schedule_card`. *(Corrected 2026-11-25 against live.)* | MATCH-1 stories 00, 01, 03 |
| F-9 | **Relaxing a rule on the map only reaches new jobs.** Requirements are frozen into the published version (reference, do not copy). A job already in flight keeps the old rule. So "the owner relaxes it to soft" does not unstick today's job. | MATCH-1 story 06, decision D-10 |
| F-10 | `work_item_time_window.constraint_type` already uses the words soft and hard (reserved, unused). Same words, different thing. Keep the meaning the same: **hard refuses, soft warns**. | REQ-1 story 04 |
| F-11 | `method.role_id` is reserved for the deferred role registry (ROLE-1). REQ-1 does not use it and does not build roles. | REQ-1 story 00, decision D-12 |
| F-12 | A plan name is unique per account, and a day is unique per (person, date). A repeat must generate a free name and can never put two days on one date. | REPEAT-1 story 02 |
| F-13 | `planner_task.status` has `needs_info`. It means "the job is missing information", not "a person should look at this copy". It is not reused. | REPEAT-1 story 05 |
| F-14 | **Unknown: how much one database transaction can hold.** A full week may be hundreds of rows. | REPEAT-1 story 00 |
| F-15 | **Publish to live reads the whole link table every time.** `live/build_publication` loads all of `planner_task_work_task` with no filter and loops slots × links (`build_publication.xs:85`). Every repeated week makes every publish slower. The publish format is `publication|v3` today (v3 added start overrides); anything matching adds is v4. | REPEAT-1 story 00, MATCH-1 story 04 |
| F-16 | **Two live gaps let work skip the shared check today.** 542 with a `timeline_id` and no override assignee never checks the day's owner (`542.xs:67-90`), so a slot can land on a switched-off copilot's day that 543 would refuse. 541 checks only when the person changes, not when the date changes (`541.xs:118-124`). Also, `assert_agent_assignable` ignores `ai_member_profile.is_paused`, which `usr/account_rank` counts. Fix all three before matching relies on the check. | MATCH-1 story 03 (prerequisite) |
| F-17 | **Unproven silent-loss risk.** 583 (line 177), `schedule_card` (line 150) and `schedule_work_task` (line 217) branch on a variable updated earlier in the same loop pass, the shape CLAUDE.md warns discards writes. If it bites, the estimate falls back to baseline minutes. Prove or clear it with a live run. | MATCH-1 story 00 |

## 4. Decisions

### Settled by the founder (2026-11-25)

| # | Decision | Answer |
|---|---|---|
| D-1 | Which comes first | **Repeat a plan**, then requirements |
| D-2 | Does a repeat keep the people on the work? | **Yes.** Every copied assignment is marked "needs review". Anyone inactive or unavailable is dropped, and their work goes to the backlog with the reason |
| D-3 | May a planner override a hard requirement? | **No.** The work stays unassigned with the reason shown. Only the owner can relax the rule to soft |
| D-4 | Hard, soft and availability | **Hard** requirements decide who is allowed. **Soft** requirements only rank the people who are left. **Availability** is checked for every piece of work, whatever it needs |

### Taken by the builder — each needs a yes or a change before its story is built

| # | Decision | My pick, and why | Needed by |
|---|---|---|---|
| D-5 | Which jobs repeat | Every job **except** outside orders, exception children and cancelled jobs. The planner can untick any job in the preview. A real customer order is not a pattern | REPEAT-1 01, 03 |
| D-6 | Which map version a repeated job reads | The map's **current** published version, not last period's. The summary lists every job whose steps changed | REPEAT-1 03 |
| D-7 | What else carries over | Order, people, manual start times and time windows (shifted) carry. **Per-job duration changes do not**: they were made "for that job only" | REPEAT-1 04 |
| D-8 | How "needs review" is cleared | One at a time, or all for a day. **Publish to live clears them**, because publishing a day is accepting it | REPEAT-1 05 |
| D-9 | Not enough hours left in the day | **A warning, not a refusal**, and that person is ranked last. Nothing enforces daily hours today, so a refusal would newly block plans that work now. A day off **is** a refusal | AVAIL-1 03, MATCH-1 01 |
| D-10 🔴 | A job in flight is stuck because nobody qualified is free | **The owner may waive one hard requirement for one job, with a reason, logged.** Without this, finding F-9 means a stuck job stays stuck until it is cancelled and re-added | MATCH-1 06 |
| D-11 | Where a requirement is set | **On a step of the map** (one stage of one row), frozen at Publish version. "Apply to the whole row" is a shortcut in the screen, not a second place to store it | REQ-1 04, 05 |
| D-12 | Roles (ROLE-1) | **Stay deferred.** A role can later be added as one more requirement. MATCH-1 replaces SCHED-1 story 04 ("suggest by role"). This needs a note in PRD §10; **not written yet, ask first** | REQ-1 00 |
| D-13 | Part-day time off | **Not built.** Whole days only | AVAIL-1 02 |
| D-14 | A plan that repeats by itself, with no click | **Not built.** A scheduled task can fail silently (OBS-1), and copying a week before the last one is finished copies its mistakes | REPEAT-1 non-goals |

## 5. Rules for building anything in this folder

On top of CLAUDE.md, not instead of it.

1. **One epic per session.** Say which model the epic needs before writing code.
2. **Verify live first** (story 00 of each epic). If live differs from the repo, stop and ask.
3. **Tests first**, then code. Run the new tests and the existing suites.
4. **Ask before** every Xano push, every schema change, every delete.
5. **Additive only.** New tables or side tables. No `updateTableSchema` on a table with trim or lower filters (it drops them).
6. **One rule, one place.** "Does this person fit this work on this day?" is one function with one TypeScript twin. Every screen, endpoint and AI tool calls it.
7. **Off until switched on.** Matching sits behind an account switch. With nothing configured, every existing plan behaves exactly as it does today.
8. **Never fail silently.** Every important step writes a success or failure event. Anything dropped or skipped is named in the response.
9. **Examples are illustrations.** "Week", "hazmat" and "turnaround" are examples. A plan can be any length; a requirement is any named thing a person can hold. No industry word goes into a table or a field.
10. **Test data:** plans 146 and 147 and the test account. Never test on map 178 or its business.

## 6. What "hardened" means in these files

Every story has: a description (the pain and what exists today), a user story (As a / I want / so that),
acceptance criteria in Gherkin, counter-measures (what could break and how it is prevented),
governance (friendly errors and events), tests, and what to keep a pulse on. Items marked
**Assumed** were not verified and must be checked before they are built. Error codes are
suggestions; register the final codes in `webapp/protype-2/src/ops/errorCatalog.json`.
