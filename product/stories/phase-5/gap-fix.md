# Phase-5 Gap Fix

Two reviews, in order:

- **[Part 1 — PLAN-2 / PLAN-3 epic review](#part-1--opus-review-of-plan-2-and-plan-3)** — each epic against its own spec. 7 findings, all fixed but one.
- **[Part 2 — full-loop walkthrough](#part-2--full-loop-walkthrough-review)** — the whole user journey, map to Execution, checked against the real screens. 9 findings. **8 built and verified live (2026-10-17); W3 deliberately left for later on the founder's call.**

---

# Part 1 — Opus review of PLAN-2 and PLAN-3

**Reviewed:** 2026-10-17, Opus 5.5, after the Sonnet build of EPIC-PLAN-2 (agent profile) and EPIC-PLAN-3 (template roster + instance copy).
**Status:** Done, except #3, which is waiting on a founder OK (to-do / in-progress / done)

## Summary

| # | Finding | Status |
|---|---|---|
| 1 | Duplicate agent names break plan creation | ✅ Fixed and verified live |
| 2 | D-2 (admin-only) misreported and not built | ✅ Fixed and verified live with a real non-admin account |
| 3 | AI agents arrive with no AI model | ⏸ Needs your OK (table change) |
| 4 | Two rejection paths never tested | ✅ Tested live, both correct |
| 5 | No automated UI tests | ✅ Written and passing. **They also caught a real bug (#7).** |
| 6 | Wrong feature on events, no event for skipped agents | ✅ Fixed |
| 7 | *(new, found by #5)* "New plan" form erased your typing | ✅ Fixed and verified |

## Findings and fix recommendations

| # | Severity | Finding | What happens | Fix recommendation | Status |
|---|---|---|---|---|---|
| 1 | **Must-fix** | Duplicate agent names break plan creation | `planner_agent` is unique by (plan, name). If a template's roster holds two agents with exactly the same display name, "New plan from template" fails with a raw database error. | (a) Reject the duplicate when it's added to a template, with a clear message. (b) Second safety net at plan creation: if names still collide (someone was renamed after being added), skip those agents and say why, rather than failing. | ✅ Done |
| 2 | **Must-fix** | D-2 misreported | The epic recommended **admin-only** for managing *other* people's agent profiles. The build had no role check, and the Test Results said "taken as recommended." | Apply the recommended default: anyone can manage their own profile; only an admin can manage someone else's, or an AI agent. | ✅ Done |
| 3 | Should-fix | AI agents arrive with no AI model | `agent_profile` has no `model_id`, so an AI agent copied into a plan has to have its model picked again in every plan. | Add a model to the profile through a new 1:1 side table (`agent_profile_model`), the house workaround for the `updateTableSchema` validator bug. | ⏸ Needs OK |
| 4 | Should-fix | Rejection paths untested | Two rejections were never exercised over HTTP: tagging a user from another account (E-PLAN-011), and editing another account's profile. | Run both live. | ✅ Done |
| 5 | Should-fix | No automated UI tests | Both epics list Playwright tests; none had been written. | Write and run the spec. | ✅ Done |
| 6 | Should-fix | Wrong feature on events | Roster events were logged as `PLAN-1`. A skipped agent left no event support could see. | Log `PLAN-3` events, plus a `warn` event whenever an agent is skipped. | ✅ Done |
| 7 | **Must-fix** *(new)* | Form erased your typing | In "New plan from a template", the form reset itself whenever the template list finished loading. Anything typed before that point was erased, and Create then failed with "Give the plan a name." This predates today (PLN-9). It breaks the CLAUDE.md rule "keep the user's typing." | Reset the form only when it opens. When the list arrives, keep the template the planner chose. | ✅ Done |

## Fix notes

### #1 — Duplicate names
- **Finding corrected while reproducing it.** The database uniqueness check is **case-sensitive**: "Jav" and "jav" both went in without error. Only an *exact* match fails. Reproduced live: template 7 had person "Jav" + AI "Jav", and creating a plan from it returned `ERROR_FATAL "Duplicate record detected"`. The transaction rolled back cleanly, so no half-created plan was left behind.
- **New function** `planner/assert_roster_names_unique` (fn 165). It compares names trimmed and ignoring capitals, which is stricter than the database, on purpose: "Jav" and "jav" on one board would confuse people too. It removes repeated ids first, so re-adding an agent already on the roster isn't flagged as a duplicate. It's built in the two-pass shape, so no conditional reads a variable set in the same loop iteration.
- **Wired into** create-template (550) and edit-template (552) → new code **E-PLAN-012**: "Two agents on this template would both be called 'Jav'. Rename one, or leave one off."
- **Second safety net in plan creation (551).** Agents whose names collide are skipped with `reason: "duplicate_name"`; the plan itself is still created. Every skipped agent now carries a reason: `not_eligible`, `not_found` or `duplicate_name`. The result screen explains each one in plain words.
- **Verified live:**

| Case | Result |
|---|---|
| Plan from template 7 (two exact "Jav"s already on it) | ✅ plan created, both skipped as `duplicate_name`, no raw error |
| New template with person Jav + AI Jav | ✅ `E-PLAN-012` |
| Add AI Jav to a template that already has person Jav | ✅ `E-PLAN-012` |
| Re-add an agent already on the roster | ✅ accepted (no false duplicate) |
| Guard alone: ids [1,2] + [2,3] | ✅ ok |

### #2 — Admin-only (D-2)
- Create (573) and edit (575) agent profile now check: managing **someone else's** profile, or an **AI** profile, needs `role = admin`. Anyone may manage their own. New code **E-PLAN-013**.
- Your account is `admin`, so nothing changes for you.
- **Verified live** with a real member account (account 3, "QA Test"):

| Case | Result |
|---|---|
| Member creates an AI agent | ✅ `E-PLAN-013` |
| Member tags themselves | ✅ allowed |
| Member edits their own profile | ✅ allowed |
| Admin edits an AI profile | ✅ allowed |

- Known gap, not fixed: the Agents screen still *shows* "Tag a teammate" and "Add AI agent" to members. If a member tries, they get the friendly E-PLAN-013 message. Hiding those buttons needs the screen to know the user's role, which it doesn't today. Small follow-up.
- The rejection comes back as an input error (400), matching how every other check in these endpoints replies. It is not a 403.

### #3 — AI model on the profile (not done, needs your OK)
CLAUDE.md requires asking before **any change to an existing table**. `agent_profile` also has trim-filtered text columns, and the documented `updateTableSchema` bug would silently drop those filters. So the house pattern applies: a new 1:1 side table `agent_profile_model` (profile → model), copied onto `planner_agent.model_id` at plan creation. That's additive and low-risk, but it's a schema change. **Reply "go" and I'll build it.**

### #4 — Rejection paths
| Case | Result |
|---|---|
| Member (account 3) tags a user from account 2 | ✅ `E-PLAN-011` "That user isn't on this account." |
| Member edits account 2's profile 1 | ✅ `404 Agent profile not found` (same answer as a nonexistent id, so ids can't be probed) |
| Member lists profiles | ✅ sees only their own account's |

### #5 — Automated UI tests
- New `webapp/protype-2/e2e/plan-templates-roster.spec.ts`:
  - **E2E-PLAN-2-01:** the Agents screen opens and lists agents.
  - **E2E-PLAN-3-01:** build a template in "Manage Templates" → add an agent → create a plan from it → the agent is on the new plan's board.
- Auth uses token injection (`E2E_AUTH_TOKEN`), same as the mobile spec. It skips cleanly without a token.
- Each run leaves one template and one plan named "E2E roster <timestamp>" behind.
- **Result:** 2/2 passing. The first run failed, and that failure was the real bug below (#7), not a test problem.

### #6 — Events
- Create/edit template now also log `PLAN-3 / add_template_agent` when the roster changes.
- Plan creation logs `PLAN-3 / skip_roster_agent` at **warn** level whenever any agent is skipped, with the list of who and why. Support can see on the Health page that a plan started short-staffed.

### #7 — Form erased your typing (found by #5)
- Cause: `CreateWorkspaceModal` reset name, date and template every time its `templates` prop changed. The list is fetched *after* the modal opens, so a planner who typed quickly lost their text.
- Fix: reset only on open. When the list arrives, keep the chosen template if it still exists; otherwise pick the first.
- Verified: E2E-PLAN-3-01 now passes end to end.

### Regression
- `npm test`: **347/347**. `tsc --noEmit`: clean.
- Playwright: roster spec 2/2, mobile spec 3/3.

### Files changed
- New: `functions/planner/assert_roster_names_unique.xs` (fn 165), `webapp/protype-2/e2e/plan-templates-roster.spec.ts`
- Backend, pushed live: `apis/planner/550_*`, `551_*`, `552_*`, `573_*`, `575_*`
- Frontend: `CreateWorkspaceModal.tsx`, `plannerApi.ts` (`SkippedAgent` type), `PlannerApp.tsx`, `errorCatalog.json` (E-PLAN-012, E-PLAN-013)

### Worth adding to CLAUDE.md (not edited — your call)
- `btree|unique` indexes in Xano compare text **case-sensitively** ("Jav" and "jav" both pass). Any "unique name" rule meant to read like a human's needs its own check in the endpoint.

## Add-on: "Start from scratch" (founder request, 2026-10-17)

Not a gap in the review — a feature request that came up while walking through the flow. The "New plan from a template" screen now has a **"Start from scratch instead (no template)"** toggle. Switching it:
- Swaps the template picker for a plain **Window (days)** field.
- On create, calls the plain phase-3 `POST /workspace` endpoint directly — no backend change needed, since that endpoint already existed and still worked (confirmed by FT-PLAN-1-09); only the frontend path to it had been removed when templates were wired in.
- Produces a genuinely empty plan: no maps, no agents, just a name and a window.

**Verified live:** toggled to "Start from scratch," created "Blank workspace test" with a 14-day window starting today → landed on its board showing **Oct 17 – Oct 30 · 14 days, Agents (0)**, nothing pre-filled.

Files: `plannerApi.ts` (new `createWorkspace`), `PlannerApp.tsx` (new `handleCreateBlankWorkspace`), `CreateWorkspaceModal.tsx` (toggle + window-days field).

`npm test`: 347/347. `tsc --noEmit`: clean.

### Test data now in your account
- Agent profiles 1–4. Profile 4 is an AI "Jav", already toggled ineligible. Profile 5 belongs to the QA test user in account 3.
- Templates 4–7 plus "E2E roster …".
- Plans 15–19, 21 plus "E2E roster …".
- Nothing was deleted (every delete needs your approval).

---

# Part 2 — Full-loop walkthrough review

**Reviewed:** 2026-10-17, Opus 5, at the founder's request after hitting gap W1 by hand.
**Method:** walked the loop as a user would — build a map → publish it → make a plan → attach the map/template → schedule → publish the day → work it in Execution — and checked **every click-path against the actual frontend code**, not the architecture or the epics. Backend capability was checked separately, so each finding says whether the ability is missing entirely or just not reachable from a screen.
**Status:** **Done** for W1, W2, W4, W5, W6, W7, W8, W9 — built and verified live on 2026-10-17. **W3 is to-do**, held out of this build at the founder's instruction ("execute part 2 minus w3"). (to-do / in-progress / done)

**Why this review exists:** the earlier reviews checked each epic against *its own* spec, and each passed. Nobody had checked whether the epics *join up* into one usable path. They don't, in three places.

## Ordered by impact

| # | Gap | Where it stops you | Backend exists? | Effort | Status |
|---|---|---|---|---|---|
| **W1** | **No way to create a job from a map** | Dead stop, mid-loop | ✅ Yes, unreachable | M | ✅ Done |
| **W2** | **No way to link an agent to a person's login** | Silent dead end at the hand-off | ✅ Yes, unreachable | S | ✅ Done |
| **W3** | **Nothing comes back from Execution** | The loop never closes | ⚠️ Partly | M–L | ⏸ To-do (your call) |
| **W4** | Performer only ever sees today | Looks broken when it isn't | ✅ Yes, unreachable | S | ✅ Done |
| **W5** | Empty Execution screen can't say why it's empty | Nobody can diagnose it | n/a | S | ✅ Done |
| **W6** | No "what's live / you have unpublished changes" on a map | Quietly wrong work | ✅ Yes, unreachable | S–M | ✅ Done |
| **W7** | Map picker offers maps it will then refuse | Avoidable error | n/a | XS | ✅ Done |
| **W8** | "Today" is UTC, not the performer's day | Wrong day near midnight | ❌ No | M | ✅ Done (phase 1) |
| **W9** | Agents screen shows admin-only actions to members | Confusing refusal | n/a | XS | ✅ Done |

---

### W1 — No way to create a job from a map *(the one that stops the loop)*

**What you do:** publish a map, make a plan, attach the map, click "Add task."
**What happens:** you get a plain text task. It looks like every other task, because it *is* — it has no connection to your map.

**Why.** There are two separate systems, and only one of them is wired to a screen:

| | What it is | Wired to UI? |
|---|---|---|
| `planner_task` | A scheduling slot: a title, a duration, a position on someone's day. Knows nothing about maps. | ✅ This is what "Add task" creates |
| `work_item` (a **job**) + `work_task` | A real instance of the work — "Quote for the Garcia party" — whose steps are generated from the map's frozen version, carrying the real instructions, done-when and durations | ❌ **No screen anywhere creates one** |

Verified: zero references to `work_item`, `job_id` or `createJob` anywhere in `planner/` — `plannerApi.ts`, `PlannerApp.tsx`, every component. Meanwhile the backend is complete and tested: `554_work_item_POST`, `555_…_GET`, `556_…_attribute_POST`, `557_…_cancel_POST`, `558_workspace_…_work_item_GET`.

**Consequence down the line:** because no job exists, Execution shows steps with no instructions and no done-when — the very things the map was built to carry. Attaching a map to a plan currently changes nothing a user can see.

**Fix:** a "New job" action in the Planner — pick one of the plan's accepted maps, name the job (e.g. "Quote for the Garcia party"), create it. Its steps then appear as schedulable items. Needs: a job-creation screen, a job list on the plan, and the schedule board able to place a job's steps rather than only free-text tasks.

**Note:** the end-to-end proof earlier in this session worked precisely because the jobs were created by direct API call, not through the UI. The backend path is proven; only the screen is missing.

---

### W2 — No way to link an agent to a person's login *(silent dead end)*

**What you do:** add an agent, schedule their day, publish it.
**What happens:** if that agent isn't tied to a real login, **nobody ever sees the work.** No warning, no hint. The planner looks finished; Execution is empty forever.

Verified: no `user_id` anywhere in the planner UI — not in `EditModal.tsx`, `types.ts`, or `plannerAdapter.ts`. `createAgent` doesn't even accept the field. `updateAgent` accepts it, but nothing calls it with it.

This is exactly what happened earlier in this session: "Rochelle" only appeared in Execution after her `user_id` was set with a raw API call.

**Partly mitigated:** agents that arrive via a template carry the login through (PLAN-2 → PLAN-3). But an agent added by hand — and *every* agent in a "start from scratch" plan — hits the dead end.

**Fix (small):** a "Who does this work?" picker on the agent, listing the account's teammates; plus a visible warning on any agent with no login ("Nobody will see this work in Execution") and on the Publish day confirmation.

---

### W3 — Nothing comes back from Execution *(the loop never closes)*

Work gets done, and the information dies there.

| What the performer produces | Who can see it |
|---|---|
| Start/done times, blocked reasons, skips | Nobody — no screen reads them back |
| Notes typed on a step | Only that same performer, on that same step |
| Variance (planned vs. actual) | Nobody |

Verified: **zero** frontend references to variance anywhere — no component, no client function. `variance.ts` (pure logic, tested) and `568_variance_work_item_…_GET` both exist and are unused.

This is the "signal" the product is built around — the thing that turns doing the work into knowing what it cost. Right now the planner has no way to see that a 25-minute step took 50, or that someone was blocked twice.

**Fix:** start small — planned vs. actual on each job, and blocked/skipped reasons visible to the planner. Full leakage maths can wait, but *something* has to come back or the loop is one-way.

---

### W4 — The performer can only ever see today

`PerformToday` calls `fetchToday()` with no date. The endpoint already accepts `?date=` — nothing passes it.

**What that means for you right now:** today is Oct 17 and you published work for Oct 19. Execution says *"Nothing is scheduled for you today."* It's correct, and it looks broken. You also can't check yesterday.

**Fix (small):** day navigation on the Today screen (‹ ›) passing the date through, and when the day is empty but work exists nearby, say so: "Nothing today. Next work: Sat 19 Oct."

---

### W5 — The empty Execution screen can't tell you why it's empty

One message — "Nothing is scheduled for you today." — covers every cause:
- you're not linked to any agent (W2)
- nothing has been published
- work exists, but for a different day (W4)
- it's published, but to someone else

For the only support person in the business, that's a dead end. **Fix:** distinguish the cases; they're all knowable from data the screen already fetches.

---

### W6 — No sign of what's live, or that you've changed it since

After publishing, the version number appears once in a message that disappears. Then:
- nothing shows which version a map is on, or when it was published
- `listMapVersions` exists and is **never called** — no version history anywhere
- **nothing warns you that you've edited the map since you published it**

That last one is the dangerous one: you tidy up a step's wording, assume it's live, and every plan keeps running the old frozen copy. Correct behaviour (that's what freezing is *for*) — but invisible, so it reads as a bug.

**Fix:** a persistent badge on the map ("Version 3, published Oct 17" / "Draft changes since v3 — publish to make them live"), and a simple version list.

---

### W7 — The map picker offers maps it will then refuse

`searchJourneyMaps` filters only on `status === 'active'`, but attaching requires a **published version**. So a draft map is offered in the dropdown and then rejected with E-PLAN-004. **Fix (tiny):** filter the picker to maps that actually have a published version, or mark the others "needs publishing" and disable them.

---

### W8 — "Today" is UTC, not the performer's day

`perform/today_for` returns the UTC date. For a performer in US Pacific, the day flips at 5pm local — work vanishes mid-afternoon and tomorrow's appears early. Already flagged (`learning-fixes.md` #4) with the rule decided (performer's timezone → account's → UTC); it just isn't built, and this walkthrough is where it bites. The function is deliberately the single place to fix it.

---

### W9 — The Agents screen shows admin-only actions to members

Carried over from Part 2 of the earlier review. "Tag a teammate" and "Add AI agent" are shown to everyone; a member clicking them gets the friendly E-PLAN-013 refusal. **Fix (tiny):** the screen needs to know the signed-in user's role and hide what they can't use.

---

## What was built (2026-10-17)

Everything below was pushed live and exercised against real data, not just typechecked. W3 was left out at your instruction.

### W1 — Jobs: the missing middle of the loop ✅

**New screen:** a **Jobs** button in the planner header (next to Agents) opens one place that does three things — start a job from one of the plan's maps, see the jobs in this plan, and put their steps on someone's day.

| | Before | Now |
|---|---|---|
| Starting work from a map | No screen anywhere. "Add task" made a plain text task with no link to the map | "New job" — name it ("Quote for the Garcia party"), pick the map, create |
| Its steps | — | Appear as real steps with the map's own wording, done-when and expected minutes |
| Scheduling one | — | Pick who and which day; the day is created if it doesn't exist |
| On the board | A **blank card** (SCHED-1 left the slot title empty on purpose, and nothing ever read the real one back) | The step's real title, with its job named in the task modal |

**Backend:** no new capability — JOB-1 (554–558) and SCHED-1 (559–560) were already complete and tested. One new function, `planner/job_step_hydration` (fn 168), reads a scheduled slot's real text back through the link, and the board (548) now returns it as `linked_steps[]`. The join lives in a function, not inline, so the backlog endpoint and the board can't drift into two different ideas of what a step says.

**Verified live, end to end:** created job 10 "W1 smoke test job" in plan 14 from map 205 → 3 steps generated, pinned to version 3 → scheduled step 25 onto a new day → the board returned `planner_task 62` with an empty stored title and the hydrated text *"Log the request in the sheet / Customer name, event date and contact are recorded"*. Also driven through the real UI by **E2E-W1-01**.

**Known limits, deliberately:** steps are placed from the Jobs screen, not dragged onto the board; the backlog drawer still lists only free-text tasks; the narrower task endpoints (546/547) still return a linked slot's blank title — only the board hydrates, and the board is what the UI loads.

### W2 — An agent's login ✅

- **"Who does this work?"** on every person agent in the Edit Agent modal, listing the account's logins.
- **"Nobody will see this agent's work in Execution"** right under the picker when it's empty — a warning, not a block. Planning ahead of a hire is legitimate; planning into silence without being told is not.
- **⚠ on the roster** in the Agents popover for any person with no login, plus one line explaining it.
- **On the Publish confirmation** — the last moment before a day is frozen and looks finished.
- Also shown in the Jobs screen when you pick an agent with no login to schedule to.

**No new endpoint.** Creating an agent posts it and then links the login through `PATCH /agent/{id}` (536), which already owns the tenancy (E-PLN-010) and one-login-per-plan (E-PLN-011) rules — rather than copying those two rules into the create endpoint, which is the kind of duplication that eventually disagrees with itself. If the link is refused the agent still exists *without* a login, and the new warning says exactly that.

**Verified live:** linking a login already used in that plan → `E-PLN-011` "That login is already linked to someone else in this plan."; clearing a link (`user_id: 0`) → accepted.

### W4 — The performer can see other days ✅

- ‹ › day navigation on the Today screen (44px targets — it's a phone screen), and a **Today** button whenever you're not on today.
- When a day is empty but work exists nearby, a **"Go to Sat 19 Oct"** button that jumps straight to it, using the real list of published days rather than guessing.
- `perform/today` already accepted `?date=`; nothing had ever passed one.

### W5 — The empty screen says why ✅

One sentence used to cover four unrelated causes. Now:

| Cause | What it says |
|---|---|
| Your login isn't linked to any agent | "You're not set up as an agent yet." + how to fix it |
| Linked, but nothing published to you | "Nothing has been published to you yet." |
| Work exists, on another day | "Nothing scheduled for you today. Next work: Sat 19 Oct." + a button |
| This day was published but nothing shows | Says plainly that this shouldn't happen |

The decision is a pure function, `diagnoseEmptyDay` in `perform/dayNavigation.ts`, tested on its own (**18 new unit tests**). The screen only renders it.

### W6 — What's live, and have you changed it since ✅

A badge next to **Publish Version** in the map editor:

- `v3 · 17 Oct` — published and matching what's on screen
- **`v3 · draft changes`** in amber — you've edited the map since you published it
- `Never published` — no plan can use this map yet

Clicking it opens the version history (`listMapVersions` existed and had never been called from anywhere).

**The amber state is the point.** Editing a published map and assuming it went live is the quiet way to be wrong: plans keep running the frozen copy, which is correct — that's what freezing is *for* — but it was invisible. The check is the server's: endpoint 521 rebuilds the live definition through *the same two functions the publisher uses* and compares hashes, so the stale check can never develop its own opinion about what the canonical form is.

**Verified live:** maps 205 (v3) and 206 (v1) re-hash byte-identically → `has_unpublished_changes: false`; map 179 (never published) → `latest_version_no: null`, false; the comparison's three branches (never published / unchanged / drifted) tested directly → `false / false / true`.

### W7 — The map picker stops offering maps it will refuse ✅

`GET /journey_map` now carries `published_version_no` and `last_published_at` per map, so both pickers (a plan's maps, and a template's maps) show an unpublished map **greyed out and labelled "— publish it first"**, with a line above saying how many are in that state.

They're shown rather than hidden on purpose: a planner looking for the map they just drew needs to see it and be told what's missing. A map silently absent from the list is the same dead end one step earlier.

The right endpoint for this (210, the account-scoped published-only search) is still permanently unreachable behind the `journey_map/{id}` route collision; the fact was added to the list that *is* reachable.

### W8 — "Today" is the performer's day ✅ (phase 1 of 2)

`perform/today_for` has always existed so this gap would have exactly one place to fix. It now takes an IANA zone and reads **the server's clock in that zone**.

The zone comes from the browser (`Intl.DateTimeFormat().resolvedOptions().timeZone`), the time does not. That distinction is the whole design: APP-1 refuses to trust a device's clock because a wrong clock silently shows the wrong day's work; a wrong zone name can't do that, and an unrecognised one falls back to UTC on its own (confirmed live — `"Not/AZone"` and `""` both return the UTC date, no error).

**This is the bug, caught in the act.** At the time of the fix the server's UTC date was 18 Oct and there was no work; in `America/Los_Angeles` it was 17 Oct — **and three real steps appeared.** Without this the performer sees an empty day every evening.

**Still missing:** the account-level default in the middle of the rule (performer's → account's → UTC). There is nowhere to store it — a timezone column is a schema change and needs your OK. When it exists it slots into that one function and nothing else moves.

### W9 — The Agents screen matches what you're allowed to do ✅

The screen now knows the signed-in user's role (from the `/auth/me` the session already holds — no extra request). A member sees "Tag yourself" and one line explaining that only an admin can tag someone else or add an AI agent; the AI section and other people's eligibility toggles are hidden or disabled rather than shown and then refused. The server still re-checks every call (E-PLAN-013) regardless.

## Tests

| Suite | Result |
|---|---|
| `npm test` (unit) | **365/365** — was 347, +18 for `dayNavigation` |
| `tsc --noEmit` | clean |
| `vite build` | clean |
| Playwright — new `jobs-and-day-navigation.spec.ts` | **4/4** (E2E-W1-01, E2E-W4-01, E2E-W5-01, E2E-W9-01) |
| Playwright — `plan-templates-roster.spec.ts` | 2/2 |
| Playwright — `perform-sessions-mobile.spec.ts` | 3/3 |
| Playwright — the other 26 specs | **Failing, and already were.** Every one dies on the sign-in page: the shared `TEST_EMAIL` login fixture is broken (proven earlier this session by running `health-page.spec.ts` unmodified). None of them touch the planner or the performer app. |

**Two real bugs were found by the new tests, not by reading the code:**

1. The Jobs screen kept the *previous* plan's jobs and maps on screen while the newly-selected plan loaded — one plan's work under another plan's name. Fixed by clearing on a plan change. (An E2E run picked up that stale list and believed it, which is how it surfaced.)
2. The first version of E2E-W5-01 raced the reload and read the loading spinner as "not empty", skipping silently every run. Fixed in the test — worth recording because a test that skips itself is indistinguishable from a test that passes in a summary line.

## Backend changes pushed live

| What | Where | Change |
|---|---|---|
| `planner/job_step_hydration` | fn 168, **new** | Reads a scheduled job step's real text back through the link (W1) |
| `perform/published_dates_for` | fn 167, **new** | Every date this performer has published work on (W4, W5) |
| `perform/today_for` | fn 138 | Takes an IANA zone; reads the server clock in it (W8) |
| `workspace/{id}/board` | api 548 | Returns `linked_steps[]` (W1) |
| `perform/today` | api 567 | Takes `tz`; returns `today`, `zone`, `my_dates` (W4, W5, W8) |
| `journey_map` GET | api 18 | Each row carries `published_version_no`, `last_published_at` (W7) |
| `journey_map/{id}/versions` | api 521 | Returns `live_hash` and `has_unpublished_changes` (W6) |

**No table was created or changed.** The one fix that would need a schema change — storing a timezone preference — is the deferred half of W8 and is flagged above.

## Worth adding to CLAUDE.md (not edited — your call)

- **`format_timestamp` accepts an IANA zone from a variable, and silently falls back to UTC for an unrecognised one** (`"Not/AZone"` and `""` both give the UTC date, no error). Safe by default, but it means a typo in a zone name is undetectable from the result — the endpoint echoes back the zone it was *asked* for, which may not be the one actually used.
- **`|set:"key":value` works on a `db.query` row object**, not just on a `var`-built map — confirmed live, and the basis of W7's addition to endpoint 18.

## Test data now in your account

- Job 10, "W1 smoke test job", in plan 14, pinned to map 205 v3, with 3 steps. One of them (work_task 25) is scheduled on a new timeline (29) for Rochelle on 2026-10-20.
- Each E2E-W1-01 run leaves one job named "E2E job &lt;timestamp&gt;" in the first plan that has a map.
- Nothing was deleted (every delete needs your approval).

---

## What I'd build first *(the original recommendation — now history)*

**W1 and W2 together.** They're the two breaks in the chain, they're adjacent in the UI, and neither needs a backend change — the endpoints exist, they just have no screen. With both done, the walkthrough I described actually works end to end: map → publish → plan → **job from the map** → schedule to **a real person** → publish → they see real instructions in Execution.

**Then W4 + W5** (half a day, removes the "it looks broken" class of problem), **then W3**, which is the real prize — the loop finally returning something.

→ W1, W2, W4, W5 and the rest were built on 2026-10-17 (see **What was built** above). **W3 is what's left**, and it is still the real prize: work gets done and the information dies there. Nothing reads back start/done times, blocked reasons, performer notes or variance — `variance.ts` and endpoint 568 both exist and are still unused.
