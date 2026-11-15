# Final review brief — Epic-23 copilot (COP-1 to COP-7)

Written 2026-11-15 by the build session, for a **Fable 5.2 review-only pass**.
To run it, paste this one line into a fresh session on Fable 5.2:

> Read `product/stories/Epic-23/FABLE-REVIEW-PROMPT.md` and do exactly what it says.

---

## 0. Your job, in one paragraph

You are the independent reviewer of work another session built and tested itself. Assume its
reports are optimistic. Your job is to find what is wrong, what is unproven but claimed, and what it
broke elsewhere - then say plainly whether each epic is safe to rely on. You are **not** here to
build, fix or tidy. A review that finds nothing is suspicious: say what you checked and how hard.

## 1. Hard rules

1. **Review only.** Do NOT push to Xano. Do NOT create, update or delete any function, tool, agent,
   endpoint, task, table, row or flag. Do NOT edit code, tests, epics or CLAUDE.md.
2. **Read-only tools are allowed:** reading repo files, `git log/diff/show`, and the Xano MCP *read*
   calls (`getFunction`, `getTool`, `getAgent`, `getAPI`, `getTask`, `getTableSchema`, `listTableIndexes`,
   `getTableContent`, `searchTableContent`, `listAPIs`, `listFunctions`, `listTools`, `listTasks`,
   `getTaskRequestHistory`, `getFunctionRequestHistory`) with `include_xanoscript: true` where offered.
3. **Do not run anything that writes.** That includes `runWorkspaceFunction`, `debugTool` (it runs the
   tool for real), and these probe scripts, which all write: every file in
   `product/stories/Epic-23/tests/` (they create plans, jobs, events, toggle levels, call the real AI).
   You MAY run `npm test` and `npx tsc --noEmit` in `webapp/protype-2` (local, no network writes).
4. **The only file you may change** is `product/stories/Epic-23/COP-1-WORK-TRACKER.md`: append ONE new
   section at the end, titled `## Final Fable review (<date>)`. Do not edit anything above it.
5. **Never print a token, ticket, password or API key** - not in the file, not in chat. If you see
   one in a file or a row, report where, not what.
6. Do not commit. Do not push to GitHub. The founder decides after reading you.
7. If something looks catastrophic and live (data being damaged right now, a secret exposed, an AI
   acting without limits), stop and tell the founder first, in one bullet, before finishing the rest.

## 2. Read these first, in this order

1. `CLAUDE.md` - especially "XanoScript constraints" and the three 🔴 blocks. Every rule there was
   learned from a live failure. **Part B of this brief is a sweep of the new code against them.**
2. `product/stories/Epic-23/README.md` - the epics, decisions D-1 to D-8, the status table.
3. `product/stories/Epic-23/COP-1-WORK-TRACKER.md` - the whole file. It holds the first Fable review
   (findings F1-F8), the live bug, and the list of decisions waiting for the founder.
4. Each epic file `EPIC-COP-1` … `EPIC-COP-7` - the Gherkin is the contract; the "Test results" and
   "Not proven" sections are the builder's own claims. Treat "Not proven" as a to-do list for you.

## 3. Scope

**Primary scope (never reviewed by anyone):** commits `8aad125` → `HEAD` on branch `new-ui`:

| Commit | What |
|---|---|
| `8aad125`, `d347c99` | COP-7 - research and read hardening (six stories) |
| `1ab705a` | The live bug fix: `exclude_middleware = false → true` in 31 endpoints; COP-5 story 03 (its own tasks) |
| `15d7414`, `fb2e528` | COP-5 story 01 - `copilot/plan_in_business`, six `planner_ops/*` functions, six `plan_*` tools |
| `4abd67e`, `a5b7b24` | COP-5 story 05 - scheduled runs (table 155, four functions, hourly task, endpoint, panel) |
| `6f1545e` | COP-5 story 06 - the copilot as a column on the plan (screen only) |
| `6758abd` + the last docs commit | COP-4 story 05 - `get_map_learnings`; capacity warning in `plan_schedule_step` |

**Secondary scope:** COP-1 to COP-4 were reviewed once (tracker, "Fable review (2026-11-15)"). Do not
redo that. Do check that findings F1-F8 are really closed by COP-7 and not just marked closed.

**Live objects made or changed in the primary scope** (workspace 1). Fetch each and diff it against
the repo file - see Part C-1.

| Kind | Id | Repo file |
|---|---|---|
| Table | 155 `copilot_run` | `static/tables/155_copilot_run.xs` |
| Function | 311 `journey/tool_gate` (changed) | `functions/journey/tool_gate.xs` |
| Function | 309 `usr/tool_caller` (changed) | `functions/usr/tool_caller.xs` |
| Function | 328 `copilot/action_types` (changed: + `scheduled_work`) | `functions/copilot/action_types.xs` |
| Function | 339 `usr/expire_tool_ticket` | `functions/usr/expire_tool_ticket.xs` |
| Function | 340 `copilot/search_query_check` | `functions/copilot/search_query_check.xs` |
| Function | 344 `copilot/plan_in_business` | `functions/copilot/plan_in_business.xs` |
| Functions | 346-351 `planner_ops/*` (create_workspace, accept_maps, create_work_item, create_timeline, create_agent, schedule_work_task) | `functions/planner_ops/` |
| Functions | 352 `copilot/open_work`, 353 `copilot/run_for_business`, 354 `copilot/run_for_account`, 355 `copilot/scheduled_run` | `functions/copilot/` |
| Tools | 39 `web_search`, 165 `label_map`, 166 `research_topic`, 167 `list_business_jobs`, 168 `get_job_variance` (changed) | `ai/tool/` |
| Tools | 169 `list_my_tasks`, 170 `record_my_task_event`, 171-176 `plan_*`, 177 `get_map_learnings` (new) | `ai/tool/` |
| Agents | 40 `Emgram Copilot` (33 tools, max_steps 18), 41 researcher | `ai/agent/` |
| Endpoint | 655 `GET copilot/runs` (journey-map group, id 4) | `apis/journey_map/655_copilot_runs_GET.xs` |
| Endpoints | 31 changed for the flag fix: journey-map 21, 33, 44, 47, 49, 62, 63, 64, 68, 73, 198, 204, 211; planner 523, 526, 529, 532, 535, 536, 538, 541, 542, 545, 550, 552, 560, 561, 573, 575, 583, 610 | `apis/journey_map/`, `apis/planner/` |
| Task | 21 `copilot_scheduled_run` (hourly, active) | `tasks/copilot_scheduled_run.xs` |

**Important about how it was pushed:** several objects (353, 354, 355, 328, 176, 177, agent 40, and
earlier the six `planner_ops` functions and six `plan_*` tools) were pushed by helper sessions told
to send the file verbatim. Nobody fetched the live source back to compare. Do that.

---

## Part A - What to CHECK (does it do what the story says?)

For every story below: read the Gherkin, read the code, and answer **built / partly / not** and
**proven / claimed / unproven** separately. A scenario with no test evidence is "claimed".

### A-1. COP-7 (research and read hardening)
- **Research can only change maps the copilot made (E-COP-051).** In `journey/tool_gate`: is the check
  reached for every write tool, including ones that take no map id, bulk tools, and `create_journey_map`?
  Can a research ticket reach a tool that writes through a *different* id (a cell id, a stage id, an
  architecture id) and skip the rule? Is `owner_user == caller` the right test for "the copilot made it"
  (what about a map a person transferred to the copilot, or a copilot-made map a person now owns)?
- **Research ticket life.** Child ticket, 900 s, ended by `usr/expire_tool_ticket`. What if the run
  throws before the expiry call? Is the parent ticket ever handed to the researcher?
- **`copilot/search_query_check` (E-COP-052).** Try to defeat it on paper: unicode digits, spaced-out
  digits, an email with `(at)`, a business title shorter than 4 characters, a title with regex
  characters, mixed case. Does it log the reason only, never the query?
- **`get_job_variance` / `list_business_jobs` / `label_map`**: uniform "not found", status whitelist,
  `slice:0:50`, source limits (E-COP-053). Check each refuses before it reads.

### A-2. The live bug fix (31 endpoints)
- The claim: behind any pre-middleware, `util.get_raw_input { exclude_middleware = false }` returns
  every *declared* input, so `$raw_input|has:"x"` was always true and omitted fields were written as
  `""`/`0`. Fixed by `exclude_middleware = true`. **Proven on 2 of 31** (538, 536) plus one full chain.
- Check all 31 files really carry the change, that no endpoint in either group still has the old
  form (`grep -rn "exclude_middleware" apis/`), and name any endpoint in a middleware'd group that
  reads raw input a third way.
- `apis/catalog/594` and `599` were left alone (no middleware on that group). Is that still true live?
- Xano rewrote two `where` clauses in endpoint 610 on save (`$has_request_id == true && …`). Read 610
  live and say whether the race guard there (the unique-index design in CLAUDE.md) still holds.
- **Damage check (read-only):** the bug was live about a day (from the USR-2 middleware attach on
  2026-11-14 to the fix on 2026-11-15). Look for real rows in that window where an optional field was
  blanked by a PATCH: `planner_agent` (name, color, capacity, user_id, model_id), `planner_timeline`
  (start_time, status), `planner_workspace`, `work_item`, journey-map tables behind the 13 journey
  endpoints. Use `plan_change_log` / `event_log` / `updated_at` to find edits in the window. Report
  counts and example ids; do not repair anything.

### A-3. COP-5 story 01 - planner tools and `planner_ops/*`
- **The six shared functions were copied from live endpoints and only one (`create_workspace`) was
  read line by line.** Read the other five against their source endpoints (554/570 accept maps,
  work_item create, 538 timeline, 535 agent, 560 schedule) and list every difference in behaviour:
  a rule missing, a rule added, a message or code changed, an event not logged, a different default.
- The builder listed bugs it saw in the **live endpoints** while copying (538 swallows any insert
  failure; 554 picks the highest version without checking it is published; 560 duration and race
  issues; 523 duplicate-name race; 570 repeated map id). For each: is it real, and did the copy
  inherit it, fix it, or change it? A copy that silently "fixes" a rule now disagrees with the screen.
- `copilot/plan_in_business`: an empty plan is allowed only for whoever created it. Can the copilot
  reach a plan in business B by first accepting a business-A map into it? Does it return `name` when
  the plan is not found (a small leak the builder noted)?
- Every `plan_*` tool: gate first, pin required (E-COP-045), Planner grant, plan in business
  (E-COP-038), live day refused (E-COP-055). Check the ORDER in each of the six files, and that
  nothing is read from the database before the gate answers.
- Capacity warning in `plan_schedule_step`: does it count cancelled or done slots, and whose capacity
  is it when a slot has an assignee override?

### A-4. COP-5 story 03 - its own tasks
- `record_my_task_event`: only a task on a **published** day whose effective assignee is linked to
  the caller; needs the Execution grant. Trace the "effective assignee" logic against
  `live/build_publication` and `perform/collect_published_items` - is it the same rule or a third copy?
- Decision D-6 is written in the epic, not yet in USR-3. Say whether the code matches the words.

### A-5. COP-5 story 05 - scheduled runs (**highest risk: an AI acting with nobody watching**)
Files: `functions/copilot/open_work.xs`, `run_for_business.xs`, `run_for_account.xs`,
`scheduled_run.xs`, `tasks/copilot_scheduled_run.xs`, `apis/journey_map/655_copilot_runs_GET.xs`.
- **Off by default?** The switch is an approval level (`scheduled_work`, default `wait`). Prove from
  `copilot/action_level` that no account can be "on" without a stored row, including for locked
  types, unknown types, business 0, and a level row left behind after a business is deleted or moved
  to another account. `run_for_account` finds candidates with its own query on
  `copilot_action_level`; `run_for_business` re-checks through `action_level`. Can the two disagree?
- **The lock.** A unique index on `lock_key`. Walk through: two ticks at once; a tick while a run is
  going; a run that dies. Then the hard one: **the stale sweep marks a run failed after 30 minutes and
  releases the lock - what if that run is merely slow and still going?** It will later patch its own
  row back to `finished` and a second run may already have started. Is an overlap possible, and how
  bad is it? (Ticket life is 15 minutes; does that bound it?)
- **Cost and runaway.** The hourly task loops every account with a copilot, sequentially. What stops
  one account's slow run from starving the others, or the task from timing out mid-loop? Does the
  COP-1 daily cap count tool calls made in a scheduled run? Is there any cap on runs per day?
- **The fingerprint guard** skips the AI when open tasks are unchanged since the last run ended. Find
  a case where it wrongly skips forever, and a case where it fails to skip (burning a call an hour).
- **The unattended run uses the full chat agent (33 tools)**, including `research_topic` and
  `web_search`. Is that acceptable with nobody watching? What is the worst thing a run can do at the
  default levels? List it concretely.
- **"A run never takes a yes from what it reads"** was not tested with injected text. Decide from the
  code whether text in a task note, a map cell or a web page can change an approval level or get an
  `approval_id` accepted. This is the scenario most worth your time.
- **The AI marked a task done that it had not done** on the first real run. The fix is an instruction
  in the run prompt, re-tested once. Chat has the softer wording. Say whether an instruction is
  enough, and what a server-side rule would look like (do not build it).
- **Counts** (`held_count`, `told_count`, `refused_count`) were only ever seen as 0. Read the three
  queries: `refused_count` counts every refused tool call by that copilot user since the run started -
  including ones from a chat happening at the same time in another business. Right or wrong?
- `$report == ""` is the only failure signal. What does the agent return when it hits `max_steps`?
- **Health.** Failures log `COP-5 run_failed` with `outcome: failure`. Confirm the Health page's
  grouping (`functions/ops/group_issues.xs`) will actually show it. A skipped run is logged as
  `outcome: rejected` with a code - is that the right outcome word for the catalog rules?
- **`GET copilot/runs`** shows run reports to anyone holding the Intelligent Layer in the account,
  and includes account rows with business 0. Should a report be admin-only? Could it contain
  another business's detail?
- **The table manifest** marks `copilot_run` as append-only although a row is patched once when the
  run ends (precedent: `tool_run_ticket`). Honest use of the manifest, or should it have `updated_at`?
- **Did the task ever fire by itself?** It was created at the end and driven by hand. Use
  `getTaskRequestHistory` for task 21 and `getTableContent` on table 155: from 2026-11-15 21:20 UTC
  there should be one `COP-5 run_tick` event per hour and one `copilot_run` row per hour for
  business 49 (test account 13, switched on). Compare the counts. Zero rows with a "successful" task
  history is the heartbeat incident again - say so loudly.

### A-6. COP-5 story 06 - the copilot as a column (screen only)
Files: `webapp/protype-2/src/planner/aiAgentModel.ts`, `useAccountCopilot.ts`,
`components/AgentKindMark.tsx`, and the edits in `PlannerApp.tsx`, `components/EditModal.tsx`,
`BacklogDrawer.tsx`, `DayBoard.tsx`, `ScheduleGrid.tsx`, `AgentsPopover.tsx`.
- Only the mark and the "Switched off" warning were seen in a browser. **The edit dialog checkbox,
  the 12 refuse-handlers and the Plan Health line were never clicked.** Read them as if untested.
- `agentUserIdToSave('person', <copilot login>)` returns 0. Trace `EditModal` → `PlannerApp.handleSaveAgent`
  → `updateAgent`: can saving a **person** column now clear its login when it should not? Can it still
  be required-and-empty? Does creating a new person column still link the login (the create path does
  a second `updateAgent`)?
- The claim "saving an AI column used to clear its login" - confirm from `git show 6f1545e`.
- `useAccountCopilot` caches for the page's life. An admin switches the copilot off in another tab:
  the planner keeps offering it until reload. Acceptable?
- The rule is not on the server. Confirm the consequence really is only "undone work" (the gate
  refuses a switched-off copilot; scheduled runs skip it) and not something worse.
- `webapp/planningFrontendv2` was not touched. Is that app still in use? If yes, this story is half done.

### A-7. COP-4 story 05 - learning (`ai/tool/get_map_learnings.xs`)
- Only the "shorter" direction was produced by a test. Read the "longer" rule as untested.
- It **ignores `is_outlier`** from the variance report and does not exclude blocked time. Should it?
- It relies on the gate (`kind: read`, with the map id) for the one-business rule and checks only
  the account itself. Confirm the gate really enforces the business pin on a read with a map id.
- Averages are truncated to whole minutes; a sample needs expected > 0 and actual > 0. Jobs pinned to
  different versions of the map may have different expected times for the same step - is averaging
  them meaningful?
- Up to 30 `function.run "variance/task_report"` calls in one tool call (4 s for 3 jobs). Will it time
  out on a real map, and what does the copilot say then?
- "My edits teach it" is not built. "Proposals are drafts" was not re-tested.

### A-8. What is NOT built - confirm the docs say so honestly
COP-6 (all of it: needs new tables and the founder's decisions on stored logins); COP-5 story 01's
time window / start time / unschedule / whole card / live-day-through-approval; COP-5 story 02's
server-side publish guard in endpoint 562; switching the six live planner endpoints to `planner_ops`;
COP-4 story 05's "my edits teach it". Check no epic, README row or tracker line claims otherwise.

---

## Part B - What to AUDIT (is it safe, whatever the story says?)

### B-1. Security and tenancy (the "another account" and "another business" questions)
For **every** new or changed tool, function and endpoint in the scope table, answer:
1. Who is the caller, and where is that established (ticket → `usr/tool_caller`, or `$auth.id`)?
   Is the account ever taken from input instead of from the user row?
2. Can it read or write a row of another **account**? Follow each query's `where`.
3. Can it read or write a row of another **business** in the same account, from a conversation
   pinned to a different one? (`pin_architecture_id`, `copilot/plan_in_business`.)
4. Does every miss answer the same thing ("not found"), or can ids be probed by the difference?
5. Is anything read before the gate has answered?
6. Is there any path where a **ticket** can be logged, stored, returned, shown to the model in a
   place it could echo, or survive its run? (`grep -rn "ticket" functions/copilot ai/tool apis/journey_map/643*`.)
7. Does the copilot's own identity ever gain a grant it should not hold? (Test account: user 26 was
   given planning + execution for the probes.)

### B-2. The gate (`functions/journey/tool_gate.xs`)
Re-derive the order of checks and confirm: caller → map ownership → architecture → business pin
(E-COP-038) → research rule (E-COP-051) → AI must be pinned (E-COP-048) → daily cap → approval
levels → audit row. For an AI identity, does **any** failed check refuse in **every** mode
(report-only never lenient for an AI)? Is the new research block in the log-suppression and verdict
conditions so a refusal is audited exactly once?

### B-3. Sweep the new XanoScript against CLAUDE.md's known traps
Go file by file through everything in the scope table. For each trap, either cite the line that
falls into it or say "clear":
- A `conditional` inside a `foreach` whose condition reads a variable `var.update`d in the same
  iteration (silently discards the branch). The builder split scheduled runs into four functions
  specifically to avoid this - check it worked, and check `get_map_learnings` (it has loops with
  many `var.update`s and no `conditional`s - confirm).
- `|get` with a **variable key** ignoring its default (must be `:null` then `??`).
- `== null` / `!= null` on a value that can be `0`, `""`, `false`, `[]`; `??` not catching `""`.
- A filter or pipe inside a `where` clause; arithmetic in a `where` clause.
- A ternary or a `|filter:arg` as a value in an object literal (drops every later key).
- A pipe nested inside a filter argument.
- `function.run` with an input left out that the caller also has by that name (inherits it).
- `db.patch` on a `json` column (merges). `db.patch` / `db.del` by a non-id field (first row only).
- `|contains:` on an array. `[index]` on any array. A `|` inside a string literal.
- `now` inside an object literal. A multi-line boolean expression.
- A header comment AND a `description =` on the same function.
- `util.get_raw_input` with `exclude_middleware = false` anywhere.
- A static path next to a dynamic path in the same group and verb (`copilot/runs` in group 4).

### B-4. Governance (every epic owes this)
- New table 155: primary key, timestamps, declared references, indexes, unique key, delete behaviour.
  Compare the live schema with the file; note whether `filters=trim` validators survived.
- Error codes E-COP-051 to E-COP-057: each in `errorCatalog.json`, one meaning each, friendly
  message, sensible owner and severity. Any code emitted that is not in the catalog?
- Events: does every important step record success or failure? Name any path in the new code that
  can end without an event (OBS-1: never fail silently).
- History tables: is anything that must never be deleted missing from `historyTables.ts`?

### B-5. Honesty of the record
Read each epic's "Test results" against its "Not proven". List every claim you could not confirm
from code, a test file or live read-only data. Mark each: *confirmed*, *plausible but unverified*,
or *contradicted* (with what contradicts it). Two known soft spots to check first: the Playwright
specs and `workflow_tests/` were **never run** in this work; and several results come from one run.

---

## Part C - COUNTER-MEASURES: what else could this have broken?

The founder's main worry. For each item: state what could break, how you checked, and what you found.

### C-1. Live drift (do first)
Fetch every object in the scope table with `include_xanoscript: true` and diff it against the repo
file. Report every difference - even whitespace-only ones Xano makes on save - and call out any
difference in logic. Local-vs-live drift has bitten this project before.

### C-2. Things existing features depend on that were changed
| Changed | Who else uses it | Check |
|---|---|---|
| `journey/tool_gate` (311) | **every** AI tool (about 60), in-app and outside | The new research block cannot fire for a non-research ticket; the response shape is unchanged; no tool reads a field that moved |
| `usr/tool_caller` (309) now returns `ticket_source` | the gate, `usr/mcp_caller` | Additive only; an old ticket row with an empty source behaves as before |
| `copilot/action_types` (328) + `scheduled_work` | the gate (`action_gate`), `GET copilot/levels`, `POST copilot/level_set`, the Approvals screen | The new type shows on the levels screen and can be set; "Suggest lowering" and the limit logic do not choke on it; no tool can accidentally declare it as its action type and run at "own" |
| Agent 40 (33 tools, new prompt sections, max_steps 18) | every copilot chat | More tools = longer prompt and more wrong-tool risk. Any section that contradicts another? Does the "one rule that matters most" still come first? |
| 31 endpoints (the flag fix) | every planner and map screen | A frontend that relied on the OLD behaviour (omitted field = blanked) now behaves differently. Search the two webapps for PATCH/POST calls that omit a field on purpose to clear it |
| `EditModal.tsx` save path | adding and editing every plan person | A person column must still save its login; the required-login rule must still fire |
| `PlannerApp.tsx` - 12 handlers got an early return | every drag, drop and "place" on the board | With the copilot unknown (`null`) or no copilot in the account, nothing may be blocked. Confirm from `isSwitchedOffCopilot` |
| `BacklogDrawer.tsx` Plan Health | the capacity tile | "Open capacity" now means people only - a number the founder may have been reading changed meaning |
| `schemaAudit.ts`, `historyTables.ts`, `errorCatalog.json`, `package.json` test list | the guard tests | Nothing was loosened to make a test pass. Check the diffs of these four files specifically |
| `perform/today_for`, `resolve_agents`, `collect_published_items` (reused, not changed) | the performer app | Confirm they were NOT edited (`git log -- functions/perform`) |

### C-3. New standing behaviour in production
- **Task 21 runs every hour for all accounts.** With every business at the default (off) it should do
  one cheap query per copilot and write one event. Confirm from the code that an "off" account costs
  no AI call, no row and no per-business queries. Estimate rows and events per day at 1, 10 and 100
  accounts, and say whether `event_log` pruning (task 11) covers `run_tick`.
- **`copilot_run` grows 24 rows a day per switched-on business** with no pruning. When does that hurt
  (`GET copilot/runs` loads 14 days, then slices)?
- **Rules that now exist twice:** six planner rules live in an endpoint AND in `planner_ops/*`. Until
  the founder approves the switch, a change to one side silently disagrees with the other. Say which
  of the six are most likely to drift, and whether `tests/cop5_tool_vs_endpoint.py` (nine bad inputs,
  answers only) is a strong enough alarm.

### C-4. The suites
Run `npm test` and `npx tsc --noEmit` in `webapp/protype-2`. Expected: 830 of 830, clean. Report the
real numbers. State plainly that Playwright and `workflow_tests/` were not run by you either, unless
you found a safe way.

### C-5. Test data and leftovers (list, do not delete)
Test account 13, business 49: map 261 (version 28); plans 44, 45, 46; jobs 143-146 (tasks 865-872);
plan people 51-55 (52 and 55 are AI, linked to copilot user 26); days 53-56; `copilot_run` rows 1-8;
level row `scheduled_work = tell` for business 49 (**scheduled work is ON in the test account**);
grants on users 22 and 26; the `publish_gate` flag for account 13. Any `scratch/*` function, probe
endpoint, test middleware or test API group still live? (`listFunctions` search "scratch".)
Confirm nothing of the kind exists in a **real** account.

---

## 4. What to write

Append to `COP-1-WORK-TRACKER.md` one section, `## Final Fable review (<date>)`, containing:

1. **Verdict table** - one row per epic (COP-1 … COP-7): *safe to rely on* / *safe with the listed
   fixes* / *not safe*, in one line each, with the single biggest reason.
2. **Findings, most serious first.** Number them R1, R2, … Each one:
   - severity: **critical** (data loss, cross-account or cross-business leak, an AI acting past its
     limits, a secret exposed) / **high** (wrong result with no error, a rule the screen enforces and
     the tool does not) / **medium** / **low**;
   - where: `file:line` and the live object id;
   - the failure, as a concrete scenario: *given … when … then the wrong thing that happens*;
   - how sure you are: **confirmed** (you traced it end to end) or **plausible** (you could not run it);
   - the smallest fix, in words - and whether it touches a live endpoint or an existing table
     (those need the founder's OK first).
3. **Things that are fine** - what you checked hard and found sound. This is evidence, not padding.
4. **Claims you could not confirm** (from B-5).
5. **Drift report** (from C-1): object, id, same / differs, what differs.
6. **Damage check** (from A-2): counts and example ids, or "none found" with what you searched.
7. **Decisions for the founder**, as plain questions, most important first, one line each.

Then reply to the founder in chat with **at most 5 short bullets** (one line each, plain words, no
jargon, no tables, no paragraphs): the overall verdict, the worst finding, whether anything is being
damaged right now, what is safe to use today, and ONE question last. The detail lives in the file.
