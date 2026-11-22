# DISC-1 — Plan discovery in the connector

**Epic ID:** DISC-1 (E2 in the founder's list)
**Status:** ✅ Built and verified live 2026-11-21. Two checks not run (see Test Results).
**Size:** S
**Model:** Sonnet 5.5 (read-only tools on a known pattern).
**Depends on:** nothing new. Uses COP-1's gate and COP-14's "one business" rule, both live.
**Read first:** `../README.md`.

---

## 1. Goal

**Pain:** the connector can add to a plan but cannot list or read one, so the plan id had to be
looked up in Xano by hand. The in-app copilot cannot list plans either.

**Win:** an AI finds the right plan, its members and its days in one or two calls, and never
asks the owner for an id.

## 2. What exists today (repo files, 2026-11-21; live not compared)

| Fact | Where |
|---|---|
| Ten plan tools exist, all writers: create, accept map, add job, add person, schedule, start day, and so on | `ai/tool/plan_*.xs` |
| No `plan_list` and no `plan_get` tool | same folder |
| Every tool passes one gate first, with `kind: "read"` or `"write"` | `journey/tool_gate` |
| "Is this plan in this business?" lives in one function | `copilot/plan_in_business` |
| "Which business is this call about?" (chat pin, or the one an outside assistant names) | `copilot/work_business` |
| The plan list a person sees, with counts | `apis/planner/524_workspace_GET.xs` |
| The plan's days (timelines), scoped task query | `apis/planner/539_workspace_workspace_id_timeline_GET.xs` |
| Plans can be archived (`is_archived`) | `apis/planner/527_…archive_POST.xs` |

## 3. Rule

**Reading a plan never changes anything, never needs approval, and never shows another
account's or another business's plan.** The tools reuse the queries the screens already use.

## 4. Do not break

- No existing plan tool changes.
- The plan screens' endpoints keep their response shape. If logic is moved into a shared
  function, the endpoint's output is compared before and after.
- An archived plan stays out of sight unless asked for (DEL-2 decision D-5: no AI reads archived
  things by default).

## 5. Non-goals

- Any write. No rename, no archive, no member edit.
- Reading tasks step by step inside a job (that is the execution tools in AIM-1).
- Searching plans by meaning. Name-contains is enough.

## 6. Stories

| File | Story |
|---|---|
| `US-DISC-1-01-list-plans.md` | `plan_list` |
| `US-DISC-1-02-read-one-plan.md` | `plan_get` |

## 7. Completion gate

- Both tools return correct data for plan 146 and plan 147, checked against the plan screens.
- A plan with no members and no days returns empty lists, not an error.
- A second account sees none of the first account's plans (real test, two accounts).
- Existing suites green. Test Results filled in.

## 8. Test Results

### 2026-11-21 (Fable 5.2)

**New in workspace 1:** tools `plan_list` (196) and `plan_get` (197), both read-only (gate kind "read").
**Changed (tool list and one short paragraph each, nothing else):** connector `journey_map` (MCP
server 8), agents "Emgram Copilot" (40) and "Emgram Copilot Strong" (43, regenerated from the
standard copy). No endpoint and no existing tool was changed.

Run with `debugTool` and real run tickets: account 2 / business 31 (plans 145–147) and a second
account, 13 / business 49.

| Test | Result |
|---|---|
| T-DISC-01-1 default list; counts for plans 146 (1 person, 3 jobs) and 147 (2 people, 2 jobs) | ✅ matches the tables. Not compared side by side with the plan screen |
| T-DISC-01-2 `include_archived` shows archived plans, marked | ✅ (account 13: 5 archived shown) |
| T-DISC-01-3 `name_contains` "BLOOM" finds both Blooming plans; no match = empty list, count 0 | ✅ |
| T-DISC-01-4 second account sees none of the first, and the reverse | ✅ |
| T-DISC-01-5 a plan in another business of the same account is hidden | ✅ by the shared rule (`copilot/plan_in_business`); no second business with plans existed in the test account to show it separately |
| T-DISC-01-6 no ticket and no business = refused | ✅ ("Access Denied" at the gate) |
| T-DISC-01-7 endpoint 524 unchanged | ✅ it was not touched (see differences) |
| T-DISC-02-1 plan 146: 1 person, 2 open jobs on map 193 version 4, 2 live days | ✅ matches the tables |
| T-DISC-02-2 empty plan (145) returns three empty lists | ✅ |
| T-DISC-02-3 another account's plan = "not found" | ✅ |
| T-DISC-02-4 date range filters days; default range is reported; a bad date gets a friendly message | ✅ |
| T-DISC-02-5 no email or user id in the response | ✅ (`has_login` yes/no only) |
| T-DISC-02-6 nothing written | ✅ by construction: neither tool has a write step. Row counts were not counted before and after |
| T-DISC-02-7 available in the app copilot and the connector | ⚠ Registered in both. **Not run** through a real copilot chat or the outside connector (a chat costs model time and acts as the copilot) |
| `npm test` in `webapp/protype-2` | ✅ 1028 of 1028 |

**Useful finding:** plan 146's two live days are far over capacity (710 and 1,420 planned minutes
against 480). That is the "order planned 11 hours" problem E5 is about; `plan_get` now shows it.

**Differences from the stories:**
- The plan-list query was **not** moved out of endpoint 524 into a shared function. The tool's rule
  (one business) is different from the screen's (whole account), and the shared part of that rule
  already lives in `copilot/plan_in_business`. Leaving 524 alone kept a live screen untouched.
- "Newest activity first" is newest **created** first (there is no last-activity field on a plan).
- The day range uses UTC dates, not the business's time zone (no time zone is stored on a plan yet; DEMAND-1 F-8).
- `job_count` in `plan_list` counts every job; `plan_get` lists open ones only and gives the total.

**Known limit:** `plan_list` asks the business rule once per plan, so about 100 plans takes ~5 seconds.
Fine for today's sizes; batch it if an account grows past that.

**Test note:** the read-only calls for account 2 ran on a ticket for user 2, so 7 rows in the tool
log show the founder as the caller.
