# COP-1 — parallel work tracker

Live list of who is doing what while COP-1 is closed out. One row per track.
Rule: two tracks never touch the same files. Backend gate/tool files belong to the review track until it reports.

| Track | What | Who / model | Files it owns | Status |
|---|---|---|---|---|
| R | Independent review of COP-1 + SEC-3 (read-only) | Opus 5.5 helper | none (reads only) | ✅ 8 findings; 1–4 confirmed by main |
| A | Team page: copilot shown as "AI", "Create copilot" button, daily-limit control | Sonnet 5.5 helper | `webapp/protype-2/src/team/*`, `src/xano.ts` (copilot calls only), new tests | ✅ built, 7 new tests, npm 796/796; not yet seen in a browser |
| F | Fix the review's confirmed findings | Opus 5.5 (main) | see below | ✅ pushed live and checked (founder OK 2026-11-14) |
| B | Health page: view of `tool_call_log` (needs one new GET endpoint) | Sonnet 5.5 helper | `src/health/*`, new endpoint file | ⏳ after F (endpoint push) |
| C | Old bug: endpoint 209 + `invoke_map` unwrapped filter | Opus 5.5 (main) | `apis/journey_map/209*`, `ai/tool/invoke_map.xs` | ✅ pushed (api 209, tool 53) and checked |
| E | Scaffold all-or-nothing (founder decision) + confirm `intent` now saves | Opus 5.5 (main) | `ai/tool/scaffold_structure.xs`, `ai/tool/scaffold_map.xs` | ✅ pushed live and checked |
| D | Delete endpoint: count owned maps as "has work" | Opus 5.5 (main) | `apis/members_accounts/20_admin_user_delete_POST.xs` | ✅ pushed (api 589); count query checked live (copilot owns 1 → counted). Not exercised end-to-end, to avoid a real delete |

## Review findings (2026-11-14)
| # | Finding | Severity | Fix (repo) | Live |
|---|---|---|---|---|
| 1 | Workflow-run tools (`get/save_workflow_state`, `export_workflow_output`) accept another account's run id | High | run must belong to the gated map; export gates on the run's own map | ✅ |
| 2 | `list_maps`/`search_maps`/`list_scenarios` show every map to a caller with account 0 | Medium | `see_all` always false | ✅ |
| 3 | Admin could change the copilot's email (then sign in as it) or role | Medium | api 19 refuses email change (E-COP-012); api 11 refuses role change (E-COP-013) | ✅ |
| 4b | `save_workflow_state` took the run owner from input | Low | owner = gate's caller | ✅ |
| 4a | ~10 tools write `agent_tool_log` with an unchecked `conversation_id` | Low | not yet | — |
| 5 | Ticket not pinned to its map (same account only) | Low | COP-3 pinning (known) | — |
| 6 | Cap fails open if the audit insert fails; some tools count 2 | Low | not yet | — |
| 7 | Health refusal-log limit is global, not per account | Low | not yet | — |
| 8 | Endpoint 209 has no owner check (pre-existing) | Low | owner check on target map and parent run | ✅ |

## Waiting on the founder (after the overnight build, 2026-11-15)
1. **COP-5 planner tools:** OK to move the planner's rules out of live endpoints 538, 542, 545, 560, 583, 613, 617, 562, 535 into shared functions? Unblocks COP-5 stories 01, 03, 05, 06.
2. **Copilot chats:** shared with everyone in the account, or private to the person who started them? (COP-3 review #5.)
3. **Research drafts:** check the time estimates in map 259 ("15 min" etc.) — they came from general practice, not your business.
4. **Endpoint 69:** the repo file is older than live (live has soft delete) — OK to refresh the file from live? Also: deleting a business does not yet check for a copilot home.
5. **Long copilot turns** can hit the server time limit and vanish with no reply; fix needs a background job (later).
6. **COP-6** left deferred, as you said. Nothing pushed to GitHub yet.

## Decided by the founder (2026-11-14)
- `intent` column added to `journey_map` by hand (confirmed live: text, trim).
- Bulk map change (scaffold): **undo everything** if any step fails — the map is never left half-changed. Track E.

## Log
- 2026-11-14 — R and A started in parallel.
- 2026-11-14 — R and A done. Fixes 1–3, 4b written; live push blocked pending founder OK.
- 2026-11-14 — Fixes pushed live (tools 33, 34, 36, 54, 57, 66; endpoints 11, 588). Checked:
  - Outside door (`cop1_review_fixes_probe.py`, test admin q): copilot email change refused E-COP-012, rename still works, role change refused E-COP-013, a person's rename/role still work, list_maps/search_maps still list. 9/9 on these.
  - In-app workflow tools (Xano `debugTool` with a real run ticket for q; run 1 is on map 244): own run loads / saves / exports ✅; same run named under map 235 (same account) refused by get, save and export ✅; save did NOT change run 1's status ✅; export with no ticket refused (Access Denied) ✅.
  - Learned: a function cannot `tool.call` a tool (it returns instantly with nothing); use `debugTool` to run a tool for a test.
- 2026-11-14 — Track E done. `scaffold_structure` (tool 7) is all-or-nothing; `scaffold_map` (56) passes the refusal on. Checked live on fixture map 236 with `debugTool` + a real ticket:
  - unknown key mixed with a good rename → refused E-COP-014 naming the key; nothing renamed ✅
  - good rename + bad lens actor type → refused E-COP-015 naming the step; rename undone ✅
  - stage REMOVE (its own inner transaction) + rename + bad step → refused; the stage, its 4 cells and the rename all came back ✅
  - good rename + add → applied (stage added with 4 cells) ✅; plain remove → applied, 4 cells removed ✅
  - `scaffold_map` with an unknown key → passes the inner message on (was crashing "Unable to locate var: r.errors") ✅; good rename → success ✅
  - `intent` now saves: `create_journey_map` with intent automation → map 257 shows it; `list_maps` intent filter returns just that map ✅
  - Proven first on scratch functions: a helper's inner `db.transaction` commits with, and rolls back with, the outer one.
  - Found live: a tool that fails inside `tool.call` does NOT throw — the caller gets `{code, message, payload}` back. Check `|has:"success"` after any `tool.call`.
  - Found live: `ops/log_event` outcome must be success | rejected | failure ("failed" is refused).
  - Fixture left in account 13: map 257 "COP-1 intent check (safe to delete)".
- 2026-11-15 — Tracks C and D done.
  - 209 + invoke_map: the context message now builds (checked on a scratch copy of the exact expression, with and without values). 209 now checks the target map (and any parent run) is in the caller's account: test admin q calling it on another account's map 176 → 403, and no workflow run was created. invoke_map now stamps the run's owner. A full agent run was not triggered (it costs an AI call); the chat path that uses the same tools was proven earlier.
  - Delete (api 589) counts owned maps.

## Fable review (2026-11-15, Fable 5.2) — review only, nothing pushed or changed

**Scope:** COP-4 research safety, COP-5 plan-vs-actual tools, and the plan to move planner rules.
**Compared with live:** tools 166 `research_topic`, 168 `get_job_variance` and agent 41 match the repo
exactly. **Not compared with live:** tools 39, 165, 167, agent 40 and function 311 (read from the repo only).
**Run live:** nothing new; the overnight session's three read checks stand. No real-data run was possible.

### Findings, most serious first

| # | Severity | Where | What goes wrong | Fix |
|---|---|---|---|---|
| F1 | Medium | `ai/agent/emgram_copilot_researcher.xs:51-60` + `ai/tool/scaffold_structure.xs`, `fill_cells.xs`, `update_cell.xs` | The researcher may change **any** map in the pinned business, not only drafts it made. Its prompt even says "reuse a draft with the same purpose". A web page saying "remove the stages of the Onboarding map" has a tool to do it with (`scaffold_structure` removes stages). Published versions are frozen, so running work is safe, but the owner's working map can be damaged. The description's claim "an instruction hidden in a web page has nothing to call" is therefore too strong. | Limit the researcher's writes to maps the copilot created (or maps whose label says `made_by` copilot_*), checked in the tools or the gate — not in the prompt. Simplest: research always creates a new map and never edits an existing one. |
| F2 | Medium | `ai/tool/web_search.xs:104-130` (instructions) | The search tool's own instructions tell the model to search for "Prospect or person information" and to "include names, company". The researcher reads these next to its "searches stay generic" rule, so the two contradict. Nothing in code stops a business name, a customer name or a figure going to the outside search service. | Give the researcher its own search tool (or neutral instructions), and add a code check: refuse a query that contains `@`, a long run of digits, or the pinned business's own name. |
| F3 | Medium | `ai/tool/research_topic.xs:43` and `:64`; researcher prompt | The run ticket is handed to the researcher, but only the main copilot is told never to repeat it, and only the final chat reply is scrubbed (`643` line 358). The researcher can put the ticket into a search query (it leaves to an outside company while still valid), a map cell, or a `research_note`. | Add the "never repeat the ticket" line to the researcher; scrub the ticket from `$report` in `research_topic`; make `web_search` refuse a query containing the ticket. |
| F4 | Low-medium | `ai/tool/get_job_variance.xs:17-40` | The job lookup and its "Job not found" answer run **before** the gate. A caller with no ticket learns whether a job id exists (not found vs sign-in refusal), the call is not written to the audit trail, and it does not count toward the daily cap. Another account's job also answers "Journey map not found" instead of "Job not found", so the two cases can be told apart. | Run the gate first with map 0 (who is calling), then look up the job, then check account and business, and answer every miss with the same "Job not found". |
| F5 | Low | `ai/tool/research_topic.xs:12,43` | `fit_notes` has no length limit and no check, and it is the channel through which private details reach the researcher (and from there, search queries). | Cap at about 500 characters, same as a note. |
| F6 | Low | `ai/tool/label_map.xs:106,133-136` | Sources are replaced correctly on an existing label (clear, then write — the json-merge rule is followed). But: on a first label with sources left out, `{}` is stored instead of `[]` (an omitted json input is `{}`); sources have no limit on count or length, so a page's long text can be stored as a "title"; and sources can never be cleared. The screen copes (`safeSources` accepts only arrays and only safe links). | Store `[]` when nothing was sent; cap at about 20 sources, title 200, url 500 characters. |
| F7 | Low | `ai/tool/list_business_jobs.xs:93-98` | No limit on rows (a busy business returns every job into the chat), jobs of deleted maps are still listed, and the status filter accepts any text (a typo quietly returns nothing). | Cap at about 50 newest, exclude deleted maps (`journey/deleted_map_ids`), refuse an unknown status. |
| F8 | Info | agents 40 and 41 | Both run `claude-sonnet-4-5`, an older model. Not a bug. | Founder's choice whether to move to a current model. |

**Checked and fine:** the business pin and ticket do carry through to the researcher (same ticket, gate
refuses anything outside the business, in any mode, for an AI identity); the researcher has no publish,
approval, plan, note, goal or research tool (no loops, no escalation); it cannot fetch a web address of
its choosing, so stolen text has no direct way back to a page's author; research calls count toward the
daily cap; the ternaries inside object literals in `research_topic` are all wrapped; `list_business_jobs`
checks account and pin correctly and returned all three keys live; `get_job_variance` refuses another
business's job (pin) and another account's job (gate plus its own account check).

### What a real-data test of plan vs actual needs (account 13 has no jobs)
1. A published map version in one test business, and a job made from it with at least two tasks.
2. A published day plan covering one task, and start/finish events with realistic times (never 0).
3. A second job in another business of account 13, and one in another account, to prove both refusals.
4. Compare the tool's figures with the report screen for the same job — they must be identical.
All of this is new test data in the test account; it needs the founder's OK to create.

### The plan to move planner rules — verdict: **yes, if** the six conditions below are met

The nine endpoints already call shared functions for most rules (`planner/assert_*`, `resequence`,
`derive_tasks`, `resolve_actor`). What is still inline is input checking, the race handling, the
transactions and the event logging. So the move is smaller than it sounds, but the inline parts are
exactly the ones that fail quietly.

**Riskiest, and why**
- **562 Publish to live** — three transactions and the frozen snapshot. The copilot must never publish to live, so there is no reason to touch it. **Leave it out.**
- **583 card schedule** — largest (456 lines), five loops, many links written in one transaction.
- **560 schedule a step** — transaction plus the estimate call.
- **613 time window** and **617 start override** — both rely on a unique index plus try/catch to survive two saves at once; wrapping that in a function changes how errors surface.

**Order:** 538, 535, 542, 545, then 617, 613, 560, 583. Never 562.

**Conditions (the missing safeguards)**
1. **Save each endpoint from live, not from the repo**, before touching it. The repo has already drifted once (endpoint 69).
2. **The workflow tests cannot be run from a session** (CLAUDE.md), so safeguard 3 promises more than it can deliver. Build a small replay set per endpoint first: real HTTP calls, recorded before, re-run after, comparing the answer, the exact error text, **and the rows and events written** — not only the reply.
3. **Include two saves at the same moment** in the replay for 538, 613 and 617.
4. **Pass every input explicitly** to each new shared function, and take the acting person as an input (never `$auth`). A function input left out silently takes the caller's value of the same name.
5. **Prove before switching.** Build the shared function, use it from the copilot tool only, show it gives the same results as the untouched endpoint on the replay set, and only then point the endpoint at it. The live planner is not changed until the proof exists.
6. **Test data first, one push per approval.** Account 13 needs jobs and a plan before any of this can be proven; each change to a live endpoint gets its own founder OK, as the safety rules already require.

**Also decide before giving the copilot any planner tool:** which approval level each planner action gets (COP-2), so "waits for you" applies from day one.

## 🔴 Live bug found and fixed (2026-11-15): "was this field sent?" was always yes

**Found** while building the COP-5 test chain: "start a day" was refused for a request that sent no status.

**Cause.** USR-2 (2026-11-14) attached an access-gate middleware to the journey-map and planner API
groups. Behind ANY pre-middleware, `util.get_raw_input { exclude_middleware = false }` returns every
declared input (with its default), not what the caller sent. So `$raw_input|has:"x"` was always true.
Proven with a probe endpoint: `{"agent_id": 5}` sent -> `with` = all four declared inputs,
`without` (`exclude_middleware = true`) = `["agent_id"]`. Changing the middleware's
`response_strategy` ("merge" -> "replace") does NOT help (tested on a throwaway group).

**Effect while live (about a day).** In 31 endpoints, a field left out of a save was treated as sent
empty: "start a day" refused (E-PLN-011); adding a plan person without a capacity refused; a partial
update of a plan person refused ("give a name"); a stage rename with no owner field would clear the
owner; a cell save without durations would reset them. Whether any real data was changed depends on
whether the screens leave fields out - NOT checked.

**Fix (founder OK'd the journey-map half; planner half ran under the build instruction).**
`exclude_middleware = false` -> `true` in 31 live endpoints and their repo files, nothing else:
- journey-map: 21, 33, 44, 47, 49, 62, 63, 64, 68, 73, 198, 204, 211 (13). Endpoint 29 does not exist live; its repo file was left alone (and has no login check - do not push it as is).
- planner: 523, 526, 529, 532, 535, 536, 538, 541, 542, 545, 550, 552, 560, 561, 573, 575, 583, 610 (18).
- 610: on save, Xano itself rewrote two `where` clauses from `($has_request_id) && ...` to `$has_request_id == true && ...` (same meaning, matches the repo). Its "already sent" check was not re-run.

**Proven after the fix:** "start a day" works (538); a plan person saved with only `user_id` kept
name, kind, capacity and colour (536); schedule (560) and the whole chain pass (7/7).
**Not proven:** the other 27 endpoints were not exercised one by one; the screens were not opened.

**Still to do**
1. Check real maps and plans edited between the gate going on (2026-11-14) and this fix for lost
   owners, durations or other blanked fields.
2. `apis/catalog` has 2 endpoints with the same flag; that group has no middleware today, so they
   work - but they will break the day a middleware is attached. Same one-word change, not done.
3. Add this to CLAUDE.md's constraints list (not edited here): **always `exclude_middleware = true`
   on `util.get_raw_input`; with `false`, any group middleware makes every `|has:` true.**
4. Endpoint 535 refuses a new plan person when capacity is left out - correct by its own rule
   (0 is outside 0-24), but its notes say capacity "defaults to 8". One of the two is wrong.

**Also confirmed today:** `$list|slice:0:N` works on a plain query list (paged results expose no keys).

## Where things stand (2026-11-15, end of the Fable 5.2 build session)

| Epic | State |
|---|---|
| COP-1 to COP-4 | Built. COP-4 story 05 (learning from plan vs actual) still open - its inputs now exist |
| COP-7 | Built and proven (all six stories). Review pass pending |
| COP-5 | 01 (six planner tools), 03 (its own tasks), 04 (plan vs actual) built and proven, incl. with the real AI. Open: 05 scheduled runs, 06 copilot column on the board, 02's server-side publish guard, the rest of 01 (time window, start time, unschedule, whole card, capacity warning, live-day changes via approval) |
| COP-6 | Not started (deferred on purpose; storing logins needs the founder) |

**Decisions waiting for the founder**
1. Switch the six live planner endpoints (523, 535, 538, 554, 560, 570) to the shared `planner_ops/*` functions? Until then each rule exists twice.
2. Check real maps and plans for fields blanked while the "was this field sent" bug was live (about a day).
3. Add the `exclude_middleware = true` rule and the `slice` fact to CLAUDE.md; correct the "pipe in a string literal" note (a pipe inside a regex pattern works).
4. Write decision D-6 (how an AI may do work) into USR-3.
5. Test-account grants changed (user 22: planning + execution; copilot 26: planning + execution; `publish_gate` on for account 13) - keep, or remove before re-running the USR-2 matrices.
6. The older open items above (chats shared or private, endpoint 69, long turns, research time estimates).

## COP-5 story 05 done (2026-11-15)

Scheduled runs are built and proven; details in EPIC-COP-5 section 7. Decision for the founder: the on/off switch is an approval level per business (off by default), not an account flag. Follow-ups: prune old run rows; tighten the chat prompt the same way the run instruction was tightened (never complete a task with no tool calls).

## Where things stand (2026-11-15, end of the build - ready for the final Fable review)

The review brief is `FABLE-REVIEW-PROMPT.md` (same folder). Nothing is on GitHub.

| Epic | State |
|---|---|
| COP-1, COP-2, COP-3 | Built and reviewed once |
| COP-4 | Built. Story 05: plan-vs-actual learning built and proven (`get_map_learnings`); "my edits teach it" not built |
| COP-5 | 01 six planner tools + capacity warning; 03 its own tasks; 04 plan vs actual; 05 scheduled runs; 06 the copilot as a column (screen only). Not built: four more planner tools (time window, start time, unschedule, whole card), live-day changes through approval, the server-side publish guard (02) |
| COP-6 | Not started. Needs new tables and the founder's decisions on stored logins - not something to build unattended |
| COP-7 | Built and proven. Never reviewed |

**New since the last list - decisions waiting for the founder**
1. Scheduled work is switched on and off as an approval level per business (off by default), not as an account flag. Keep it that way?
2. The hourly task (21) is live for every account. With every business off it only writes one event an hour. Leave it running?
3. An AI can still mark its own task done on the strength of an instruction only. Add a server rule (for example: no "completed" without a tool call in between)?
4. "Switched-off copilot is not given new work" is enforced in the planner screen only. Add it to the planner endpoints with the other live-endpoint changes?
5. COP-6: approve the tables (a connections library, a per-business switch, a write-only secret store) and decide where logins are kept.
6. Test account: scheduled work is ON for business 49 and writes a row an hour. Switch it off after the review?

**Earlier decisions still waiting** (see "Where things stand" above this one): switching the six live planner
endpoints to `planner_ops/*`; checking real data for fields blanked by the middleware bug; the CLAUDE.md
additions; writing D-6 into USR-3; the test-account grants; catalog endpoints 594 and 599.


## Final Fable review (2026-11-15)

Review only. Nothing was pushed, run, created, changed or deleted in Xano; no code, test, epic or
CLAUDE.md was edited; nothing was committed. This section is the only change.

**How it was done.** Five read-only helper passes plus my own reading: (1) live source of 19
functions/table/task/endpoint against the repo; (2) live source of 14 tools and both agents; (3) all
31 flag-fix endpoints live, plus every endpoint in the journey-map (100) and planner (64) groups;
(4) the six `planner_ops/*` functions against their source endpoints, `plan_in_business`, six `plan_*`
tools; (5) the screen changes, the guard files, `npm test` and `tsc`. I read the gate, the ticket
functions, the research and search checks, all four scheduled-run functions, the approval gate, the
own-task tools and the learning tool myself, and read live rows in `copilot_run`, `event_log`,
`tool_call_log`, `planner_agent`, `planner_timeline`, `journey_map`. **Nothing was executed**, so every
"plausible" below is a code reading that still needs one run to prove.

**Suites.** `npm test` 830 of 830, `npx tsc --noEmit` clean (real numbers, run once). Playwright specs
exist (`webapp/protype-2/e2e/`) and `workflow_tests/` exist; **neither was run by me either.**

### 1. Verdict

| Epic | Verdict | Biggest reason |
|---|---|---|
| COP-1 identity, gate, cap | Safe to rely on | Live gate matches the repo; an AI is refused on any failed check; all four mode switches are "enforce" |
| COP-2 approval levels | Safe with the listed fixes | The gate works, but only `publish_map` declares an action type - every other level on the screen does nothing (R1) |
| COP-3 home and chat | Safe to rely on | The business pin is enforced in the gate for reads and writes (seen refusing live) |
| COP-4 think and learn | Safe with the listed fixes | Notes become standing instructions with no level (R5); learning ignores outliers (R9) |
| COP-5 plan and act | Planner tools: safe with fixes. Scheduled runs: **keep off in real accounts** until R1 and R2 are fixed | Nothing can be held for approval, and "done" rests on an instruction |
| COP-6 connections | Not built | The docs say so honestly everywhere I looked |
| COP-7 research and read hardening | Safe to rely on, with known limits | F1-F7 are really closed in code and live; the search check stops obvious shapes only (R13) |

No cross-account or cross-business read or write path was found in any new tool, function or endpoint.

### 2. Findings, most serious first

**R1 - HIGH - confirmed. The approval levels are not connected to any new tool.**
- Where: gate calls in `ai/tool/plan_create.xs:29`, `plan_accept_map.xs:26`, `plan_add_job.xs:33`,
  `plan_add_person.xs:40`, `plan_start_day.xs:38`, `plan_schedule_step.xs:34` (tools 171-176),
  `record_my_task_event.xs:27` (170), `save_note.xs:17`. `functions/journey/tool_gate.xs:380` runs the
  approval gate only when `act_type` is sent. `grep act_type ai/tool` finds one tool: `publish_map`.
- Given the owner sets "Draft a plan", "Update assigned work" or "Write an internal note" to
  "Waits for you"; when the copilot drafts a plan, completes a task or saves a note, in chat or in a
  scheduled run; then it happens at once, nothing waits, nothing is listed under "What the copilot did".
- Consequences: story 05 scenario 1 ("holds the rest") cannot happen - there is nothing to hold, which is
  why `held_count` and `told_count` were only ever 0. Decision D-6 ("each action type still follows its
  level") is not what the code does. "A change to a live day waits for me" is a flat refusal.
- Fix: pass `act_type` (+ payload and summary) in those eight gate calls and call `copilot/action_finish`
  after the write. Tool pushes only; no endpoint or table change.

**R2 - HIGH - confirmed (seen live). An AI can mark its own task done, or skipped, with no work behind it.**
- Where: `ai/tool/record_my_task_event.xs:204` (170); the only guard is a sentence in
  `functions/copilot/run_for_business.xs:410` (353). Chat has softer wording (`emgram_copilot.xs:71`).
- Given a task assigned to the copilot that needs something in the real world; when a run or a chat
  decides it is done; then it is recorded "completed", the job can flip to completed, and plan-vs-actual
  takes it as real. `copilot_run` row 2 did exactly this ("Deliver the order", event 9097).
- An instruction is not enough: one re-test passed, and the same model reads injected text.
- A server rule would look like (not built): for an AI identity, "completed" needs (a) the step marked
  as doable by the copilot in the pinned map version, or (b) at least one allowed write-tool call by
  that identity between its "started" and "completed" events for that task; otherwise the event is
  stored as waiting for a person. Wiring R1 (`work_update` at "tell") at least lists every completion.
- Fix touches one tool and one shared function; no table.

**R3 - HIGH - confirmed by reading. Saving an AI column can silently unlink the copilot.**
- Where: `webapp/protype-2/src/planner/aiAgentModel.ts:318-319`, `components/EditModal.tsx:423`,
  `PlannerApp.tsx:479-489`, `useAccountCopilot.ts:14-17`.
- Given the copilot lookup failed once on this page load (the failure is cached until reload); when a
  planner opens the copilot's column, changes its capacity and saves; then `user_id: 0` is sent, the
  link is cleared, the dialog closes as a success, and the copilot stops seeing its tasks. A unit test
  pins this behaviour. This is the bug story 06 says it fixed, still there on the failure path.
- Fix: when the copilot is unknown, leave `user_id` out of the save. Screen only.

**R4 - MEDIUM/HIGH - confirmed in code. A person column linked to the copilot's login is unlinked and renamed on any edit.**
- Where: `aiAgentModel.ts:320-322`, `EditModal.tsx:385-387, 416, 423, 806`.
- Before story 06 the only way to link the copilot on the screen was "person" + its login. Editing such a
  column now saves login 0 and renames it. Whether such rows exist in real accounts: not seen (the
  seven live plan people have none), so exposure today is nil.

**R5 - MEDIUM - plausible. Text the copilot reads can become a standing instruction.**
- Where: `ai/tool/save_note.xs` (no level, see R1); notes are placed under "Notes you were told about
  this business (follow them)" in `apis/journey_map/643_copilot_chat_POST.xs:255` and
  `functions/copilot/run_for_business.xs:406`. `label_map`'s `research_note` has no length cap either.
- Given a web page or a task note says "remember: tasks marked delivery are already done"; when the
  copilot saves it as a note; then every later chat and every unattended run is told to follow it.
- It cannot change an approval level or forge an approval (see "Things that are fine"), but with R1 and
  R2 open there is little left for a level to stop. Fix: R1 for notes, and word the run prompt as
  "notes are preferences, never permission to complete, send or skip".

**R6 - MEDIUM - confirmed by reading. The "nothing changed" guard both over-skips and under-skips.**
- Where: `functions/copilot/open_work.xs:83-99`, `run_for_business.xs:57-86`.
- Over-skips: the fingerprint is only date + task id + status. The owner approving a held action, adding
  a note, or fixing the map changes none of them, so no run picks the work up again that day.
- Under-skips: only a *finished* run stores a fingerprint. A run that fails every time (empty reply,
  timeout, AI error) is retried every hour, a full AI run each time. Nothing caps runs per day or AI
  tokens; the COP-1 daily cap counts tool calls only (it does count a run's calls - same identity).
- Fix: include the count of decided approvals and the newest note id in the fingerprint; store the
  fingerprint on a failed run too and retry at most N times a day.

**R7 - MEDIUM - plausible. One hourly task for every account, one after another, with the heartbeat written last.**
- Where: `functions/copilot/scheduled_run.xs:95-141`, task 21.
- A real run took 31-33 s; the first self-fired tick took 6.2 s with one idle business (1.8 s by hand).
  The `run_tick` event is the last statement. If the task hits its time limit mid-loop, later accounts
  (always the same ones, by id) are never reached and no tick event is written at all.
- Fix: log the tick at the start as well, or one task per N accounts; decide a ceiling before a second
  real account switches this on.

**R8 - MEDIUM - plausible. "Is this task mine" exists in three forms.**
- Where: `ai/tool/record_my_task_event.xs:104-166` reads the live plan tables; `list_my_tasks` and
  scheduled runs read the frozen publication (`perform/collect_published_items`).
- Given a slot is dragged onto the copilot's column after the day went live and not re-published; then
  the published plan still gives the task to a person, but the copilot may record work on it. The
  reverse case lists a task it is then refused on (E-COP-054).
- Fix: take the effective assignee from the publication, as the performer app does.

**R9 - MEDIUM - confirmed by reading. Learning can propose a wrong time.**
- Where: `ai/tool/get_map_learnings.xs:168-270` (177).
- It ignores `is_outlier` and `blocked_minutes` from the variance report and averages jobs pinned to
  different versions. Three samples where one task sat open overnight give "longer", average hundreds
  of minutes. Averaged "expected" can match no version of the map.
- Up to 30 report calls in one tool call (4 s for 3 jobs, so about 40 s for 30) inside a chat turn that
  can already hit the server limit and vanish. The "longer" rule is the mirror image and untested.
- Fix: drop outliers, subtract blocked time, use the newest version only (or group by version).

**R10 - MEDIUM - confirmed. The planner tools do not always answer like the screen.**
- Capacity 0 becomes 8 (`plan_add_person.xs:107-117`; screen: E-PLN-009). Duration 0 means "not sent"
  (`plan_schedule_step.xs:120`; screen: E-SCHED-002). An empty start time takes the default
  (`plan_start_day.xs:99`; screen: E-PLN-010). Dates are text: "2026-02-31" passes the shape check and
  most likely ends in a raw database error (plausible).
- `plan_schedule_step` writes the slot first and computes the capacity warning after, so "places it
  only if I say so" is not met, and a failure in the warning leaves the step placed.
- All five builder-listed endpoint bugs are real and **inherited unchanged** (none silently fixed), with
  one correction: 570 with a repeated map id does not insert twice - the unique index fails the whole
  transaction with a raw error. "554 picks an unpublished version" is mostly not real (versions have no
  draft state).

**R11 - MEDIUM - confirmed. Two test claims are weaker than written.**
- `tests/cop5_tool_vs_endpoint.py` calls nine endpoints and prints the answers. There is no tool side,
  no assert, no exit code, fixed ids. It is not an alarm for the two copies drifting.
- `tests/cop7_hardening_probe.py` is named as COP-7's probe script; the file does not exist.
- The "nothing has changed" proof used a hand-set row: `copilot_run` row 6 stores fingerprint
  `866:in_progress`, but its own finish event (9108) says `open_after: 0`, and the task was unblocked by
  a person 30 s later (event 9110).

**R12 - MEDIUM - confirmed by reading. Story 06 screen gaps.**
- The copilot lookup is cached for the page's life and Manage users is in the same app: switch the
  copilot off, go back to the planner, and it is still offered; switch it on, and the planner keeps
  refusing until a hard reload (`useAccountCopilot.ts:10-19`).
- Ctrl/Cmd+Enter saves a stale "link copilot" tick (`EditModal.tsx:239`, dependency list).
- An AI column linked to some other login is shown ticked and re-linked to the copilot on save
  (`EditModal.tsx:173`).
- "Not offered when assigning" is not built (it is offered, then refused). Three paths are unguarded:
  assignee override on task save (`PlannerApp.tsx:636-659`), on backlog create (`:1042-1048`), and
  Publish to live of the copilot's day (`:714`, `:1167`). The guard also blocks moving the copilot's
  own existing day (`:1084`, `:802`).
- Turning scheduled work on has no confirmation step on the Approvals screen.

**R13 - LOW - confirmed by reading. What the search check lets through** (`functions/copilot/search_query_check.xs`, 340):
figures with separators ("1,250,000"), an address written "name (at) domain", digits in other scripts,
part of the business name (only the full title is matched), any title under 4 characters, and every
customer name. A range like "2020 - 2025" is refused by mistake. It logs the reason only, never the query.

**R14 - LOW - confirmed. Small probing differences.** `copilot/plan_in_business.xs:11-15, 85-91` returns
another account's plan name on a miss (no tool reads it today). `plan_schedule_step.xs:60-64`: a missing
day says "Day not found", another account's day says "Plan not found".

**R15 - LOW - confirmed. Counts and records.** `refused_count` counts every refused call by that
identity since the run began, including a chat in another business (`run_for_business.xs:479-482`).
The audit row does not store the pinned business or the run, so a call cannot be tied to a run. Pin,
research, unpinned-AI and approval refusals write the audit row but no Health event. E-COP-057 has one
message for three situations ("did not finish" is wrong for "could not start"). If the lock insert
loses to a run that ends a moment later, the skip is recorded as a red failure. Event 9041 was logged
as E-COP-040, which now means something else.

**R16 - LOW - plausible. An AI tool in the chat still uses the old flag.** `ai/tool/update_stage_contract.xs:42`
has `exclude_middleware = false` and is on agent 40, which runs behind the gated chat endpoint 643. If a
tool sees the request's raw input the way an endpoint does, a contract update that leaves a field out
blanks it. Not traced; needs one run.

**R17 - LOW - confirmed. Leftovers and growth.** `copilot_run` has no pruning (24 rows a day per
switched-on business; `GET copilot/runs` loads 14 days then keeps 30). A business with a stored level
keeps running after it is deleted. The table is marked append-only though a row is patched when a run
ends, and can be patched twice (stale sweep, then a late finish). 39 `scratch/*` functions and two
scratch API groups (29, 30) are still live, including ones that mint a token, create users and corrupt
rows on purpose - reachable only with workspace access, and all older than this work.

### 3. Things that are fine (checked hard)

- **The gate order** is caller, map ownership, architecture, business pin, research rule, AI must be
  pinned, daily cap, approval level, audit row. An AI is refused on any failed check in any mode. A
  research refusal is audited exactly once. The response shape is unchanged; `ticket_source` is additive
  and an old ticket with no source behaves as before. The research block cannot fire for another ticket.
- **Research can only change maps the copilot made.** All four of the researcher's write tools pass the
  map id and `kind: write`; none writes through a cell, stage or architecture id. A new map is stamped
  with the caller as owner. A sub-map under a person's map is refused. Owner = caller is the safe-side
  test: a map a person now owns is refused; a map handed to the copilot is editable.
- **The researcher never gets the chat's ticket.** Its own ticket lives 15 minutes, is ended after the
  run (also when the run throws), and both are scrubbed from the report. Agent 40 has no `web_search`.
- **No text can approve anything.** Levels come from the action type in the gate. An approval id must be
  this account's, this tool's, this map's, this type's, approved by a person, unused (unique claim), with
  the exact input. No tool sets a level. Publish stays person-only.
- **Scheduled runs are off unless a level row says otherwise.** Unknown type, business 0, a locked type
  and "no row" all resolve to "wait". The two "is it on" checks cannot disagree in the unsafe direction:
  a stale or foreign row fails the account check and writes nothing. An "off" account costs two small
  queries, no row, no AI call.
- **Two runs cannot act at once.** The unique index on `lock_key` exists live. A slow run marked stale
  at 30 minutes has had a dead ticket for 15, so a second run never overlaps its actions; the late
  finish only rewrites its own row.
- **Worst case for an unattended run at default levels** (concrete): rewrite or strip the unpublished
  content of any map in that business; create draft plans, jobs, people and days; complete, skip or
  reopen its own tasks; save notes; send general web searches. It cannot publish, touch another
  business or account, change a live day, change a level, or use a person's task.
- **The 31-endpoint fix** is one word in each of 31 files and is live on all 31; no endpoint in either
  gated group still has the old form. 610's race guard still holds (count taken with the checks; unique
  index on parent + sequence exists live).
- **Tenancy in the new tools:** user and account always come from the gate; nothing is read before it;
  `plan_add_person` cannot link a login; `plan_start_day` cannot set a status; a business-B plan cannot
  be reached by accepting a business-A map.
- **Guard files:** nothing loosened; additions only. `perform/*` was not edited. Every E-COP code emitted
  is in the catalog. The run report renders as plain text. `planningFrontendv2` is not in use (no Xano
  calls since October) - story 06 is not half done on that account; CLAUDE.md and the PRD still name it.
- **Trap sweep:** clear in the scheduled-run functions, `get_map_learnings`, the gate, the search check
  and the three read tools. Two inherited hits in `planner_ops` (`create_agent.xs:138-148`, proven
  working live in the endpoint; `schedule_work_task.xs:165-176`, no live proof, same in endpoint 560).

### 4. Claims I could not confirm

| Claim | Status |
|---|---|
| The hourly task fires by itself | **Confirmed once**: 21:20:01 UTC, one history entry, one `run_tick`, one row (9). Second firing not yet due when I stopped |
| "It blocked the task" on the re-test | Confirmed (tool call 257, event 9107) |
| "Nothing has changed" proven | Plausible; the row it relied on was hand-set (R11) |
| Same answers as the screen, 9 of 9 | Plausible; the script compares nothing (R11) |
| `scratch/cop5_run_probe` (356) still exists | **Contradicted** - 356 is not live |
| COP-7 probe script exists | **Contradicted** - no such file |
| A run that holds an action; counts above 0 | Unproven, and unreachable today (R1) |
| Injected "pre-approved" text changes nothing | Holds by code for approvals; not for "done" (R2, R5) |
| What the agent returns at `max_steps` | Unproven; an empty reply fails, partial text counts as "finished" |
| The "longer" learning rule; a plan person override; the Execution or Planner grant missing | Unproven |
| Edit dialog tick, 12 handlers, Plan Health line | Unproven in a browser; three bugs found by reading (R3, R4, R12) |
| 27 of the 31 fixed endpoints behave | Plausible; source is correct live, none exercised |

### 5. Drift report

| Object | Result |
|---|---|
| Functions 309, 311, 328, 339, 340, 344, 346-355 | Same logic. Only Xano's save-time formatting |
| Tools 39, 165-177 | Same logic |
| Agents 40 (33 tools, 18 steps) and 41 (8 tools, 10 steps) | Same; prompts word for word |
| Table 155 | Same; trim kept on all five text columns; unique index on `lock_key` live |
| Task 21 | Same; active, hourly from 21:20 UTC |
| Endpoint 655 | Same; no dynamic `copilot/{x}` route exists to shadow it |
| 31 fixed endpoints | 18 identical; 13 formatting only |

Xano's rewrites to know about: it drops `== true` in conditions, expands objects, and **removes
parentheses around a piped value inside an object** (for example 583's `($c.duration_minutes ?? 0)`).
Never paste live text back into the repo and push it - that is the CLAUDE.md "drops later keys" trap.
Compared by reading, not by a byte diff.

### 6. Damage check (the "was this field sent" bug, 14 Nov about 17:50 UTC to 15 Nov about 16:20 UTC)

- **Plans: none found.** Every plan person and day in a real account was last changed between
  27 October and 2 November; names, capacity, login, start time and status are intact (people 48, 49;
  days 40-45). Nothing in `plan_change_log` in the window.
- **Maps: not fully checked.** Real account 2 has ten maps touched on 14 November (225-234), some
  inside the window. Their map-level fields are intact. Stage owners and cell durations on those maps
  were not read row by row.
- All other activity in the window was test account 13.
- Separately, the fix exposes clears that never worked: a cleared link label (`ArchitectureGraph.tsx:174`)
  and a cleared cell duration (`App.tsx:1642, 2241`) are dropped by the screen; a cleared business
  description or cost rate is most likely dropped by the server's empty-text filter (endpoints 68, 33).

### 7. Test data and leftovers (listed, not deleted)

Test account 13 only: map 261 and version 28; plans 44-46; jobs 143-146; plan people 51-55; days 53-56;
`copilot_run` rows 1-9; scheduled work **ON** for business 49 (task 866 is in progress, so each hour
writes one "nothing changed" row and no AI call); grants on users 22 and 26; the `publish_gate` flag.
Nothing of the kind was found in a real account.

### 8. Decisions for the founder

1. Keep scheduled work off in real accounts until levels are wired (R1) and "done" has a server rule (R2)?
2. Wire the levels to the eight tools now (tool pushes only)?
3. Which server rule for an AI completing a task: proof of work, or always "waits for a person"?
4. Fix the copilot-column save (R3, R4) before anyone edits a copilot column?
5. Should notes need your OK before the copilot follows them (R5)?
6. Open maps 225-234 and check stage owners and durations, or have them read row by row?
7. Switch scheduled work off for test business 49 and remove the test data?
8. Is a run report for everyone with the Intelligent Layer, or admins only?
9. Delete the 39 scratch functions and the two scratch API groups?
10. The earlier open items still stand: the six-endpoint switch, catalog 594/599, the CLAUDE.md additions.


## R3 and R1 fixes - paused mid-way (2026-11-15, Fable 5.2)

Nothing is committed. `npm test` 847 of 847, `tsc` clean. Copilot (user 26) is switched ON.

**R3 / R4 / part of R12 - done, screen only, NOT clicked in a browser.**
- `aiAgentModel.agentUserIdToSave` now returns `null` = "leave the login as it is"; the save then omits `user_id` (endpoint 536 keeps it).
- Covers: copilot lookup failed (R3), a person column linked to the copilot login (R4, no rename either), an AI column linked to another login, the stale Ctrl+Enter save.
- Not done from R12: the cached copilot lookup, the three unguarded paths, "not offered when assigning".

**R1 - 7 of 8 tools live and proven. `plan_schedule_step` (176) is NOT pushed.**
- 🔴 Drift on purpose: `ai/tool/plan_schedule_step.xs` in the repo is already wired; live tool 176 is the old one. Push it next, then test (own level + one refusal).
- Bigger than the review said. The review's "tool pushes only" would have used the DEFAULT levels, because these tools name no map and no business. Also changed:
  - `journey/tool_gate` (311): the level is looked up in the pinned business when the tool names none.
  - new `copilot/action_close` (358): marks the action executed / failed and passes the tool's error on with its own kind.
  - `copilot/action_types` (328): `plan_draft`, `note_internal`, `work_update` now say `wired: true`.
- Each tool: `approval_id` input, action type + exact input + a summary to the gate, body inside `try_catch`.
- Proven live with `debugTool` as the test copilot, business 49:
  - `save_note` (163): tell -> listed; bad note -> "failed"; wait -> E-COP-020, changed input -> E-COP-027, exact input -> saved and "executed", again -> E-COP-030; own -> no row.
  - `record_my_task_event` (170): note on task 866 -> "told"; not its task -> refused, "failed"; bad event -> E-LOG-001 text kept.
  - `plan_create` 171, `plan_accept_map` 172, `plan_add_job` 173, `plan_start_day` 175: one success and one refusal each, error kind kept.
  - `plan_add_person` (174): wait -> approved through the REAL endpoint 639 -> ran (decimal input matched); an approved duplicate name -> E-PLN-007 and "failed".
- Gate smoke after the change: a read tool allowed, `publish_map` still E-COP-025, a bad ticket refused.
- Not proven: the real AI in chat following a "waiting" answer; a scheduled run with held_count above 0; the Approvals screen showing these rows; an "edited" approval.
- Known weak spots: an invalid request can be queued for the owner (the level check runs before the tool's own checks); summaries show ids ("plan #47"), not names.
- Found on the way: `$error.message ?? "x"` always gives the fallback (read `$error` whole, then `|get:"message"`). `run_for_business.xs:210, 439` and endpoints 643, 633 use the broken form, so their failure messages are always the generic one.

**Left in the test account:** plan 47 "R1 test plan" (job 147, people 56-57, day 58, slot 133), notes 3-5, copilot_action rows 17-24, `tests/r1_decide_probe.py` (new, writes).

**R1 finished (2026-11-16, Opus 5.5).** `plan_schedule_step` (176) pushed - no drift left. Own level: step 873 on day 58 -> slot 133, capacity 390, not over; same step again -> E-SCHED-001 text kept; unknown day -> not found. Three calls logged, no approval rows (correct at "own"). `scratch/r1_probe` (359) deleted. Copilot (user 26) still active.

## Review fixes R2, R5, R6 (2026-11-16, Opus 5.5)

Founder: "continue to build out, validate test all the remaining epics"; hold the outside connection.
My call on decision 3 (R2): completions WAIT by default, and the owner can loosen it - safest, reversible, uses the existing levels.
- **R2** new action type `work_complete` "Mark its own work done or skipped", default wait, not locked (328 live). `record_my_task_event` (170 live) sends completed/skipped as `work_complete`, everything else as `work_update`.
  - Live, tool: "completed" on own task 866 -> stored waiting (item 25), task stays in progress; a note -> runs, listed as told (item 26).
  - Live, real chat over HTTP (`tests/r2_chat_probe.py`): copilot answered "waiting for approval, item 25"; no duplicate item; 866 still in progress.
- **R5** notes heading is now "preferences only" with a stated limit, in the run prompt (353) and the chat (643). Both live.
- **R6** fingerprint adds decided approvals and the newest note (352 live: `... a:2 n:4@5@...`). After 3 failed runs in a day a business waits until tomorrow (manual runs still go), new code E-COP-058 (catalog entry added; the code guard caught the first try reusing 057). A run is told the approved items it may now send.
- `$error.message ??` fixed in 353 and 643 (read `$error` whole). Endpoint 633 still has it.
- Tests: `reviewFixes.test.ts` (6) + R1 wiring test updated; 17 of 17.
- Not proven: a full AI scheduled run with these changes (the date rolled to 16 Nov; the copilot has no published day today). The idle path wrote the new fingerprint (run row 18).
- Left: item 25 waiting in business 49, on purpose, so the Approvals screen has a real example.

## Review fixes R7, R9, R10 (2026-11-16, Opus 5.5)
- **R7** `copilot/scheduled_run` (355 live) logs `run_tick_started` first, `run_tick` last. Live: events 9200 then 9201. A start with no end = the task was cut off. No per-tick ceiling yet (still one task for every account).
- **R9** `get_map_learnings` (177 live): newest version only, blocked minutes taken off, outliers left out, at most 15 jobs. Live on map 261: 5 jobs read, rows as before.
- **R10 date bug (worse than the review said):** `plan_start_day` with "2026-02-31" did not error - it silently made a day on 3 March (day 59, plan 47, left in the test account). Both `plan_start_day` (175) and `plan_create` (171) now read the date back and refuse one that does not exist. Live: 2026-02-30 and 2026-04-31 refused; 2026-03-03 still works. Probe function 360 deleted.
- **R12** (screen): copilot lookup no longer kept for the page's life (failures retried, 1-minute reuse, Manage users on/off refreshes it); task-save assignee, backlog create, Publish to live / republish / publish day now refuse a switched-off copilot; its own day can still move to another date; switching scheduled work on asks first. `npm test` 865/865, tsc clean. NOT clicked in a browser.
- **R14** `copilot/plan_in_business` (344 live) returns no name, count or archived flag on a miss. Live: account 999 -> `name: ""`.
- **R16 probe found a different, real bug** in `update_stage_contract` (tool 70): the flag was fine (an omitted field is kept - proven), but "pass null to clear" NEVER cleared - null and "" both became null, and db.edit keeps the old text when given null. Now clears by writing "". Live on stage 1957: set, then null -> "", owner lens kept. No other file has the pattern.
- **R13** `copilot/search_query_check` (340 live): "1,250,000" now refused; "jane (at) example" refused as an address; a year range "2020 - 2025" now allowed (phone rule counts 9+ digits, not characters). Live with a research ticket: all four as expected. Still not caught: other scripts' digits, part of a business name, short names, customer names.
- **Browser (this session's own app on port 3011, signed in as the test admin, account 13):** Approvals "Waiting for you" lists item 25 "Record 'completed' on its task #866" (first time a held copilot completion was seen on screen); Approval levels for business 49 shows the new "Mark its own work done or skipped" row; the Connections section lists the probe entry as "Off - needs a login first". No console errors. The pane was hidden, so tab/select changes were driven from the page, not mouse clicks. The planner R3/R12 screens were NOT clicked.
## Handoff 4-A - two server rules (2026-11-16, Opus 5.5 + a helper agent)
- **Rule 1** `copilot/assert_person_only` (361) in Publish to live 562: user 26 refused (E-COP-025, event 9257), user 22 passes to publish's own checks. Publish success path NOT re-proven (no ready day).
- **Rule 2** `planner_ops/assert_agent_assignable` (362, new code **E-COP-059**, same words as the screen) in `planner_ops/create_timeline` (349), `planner_ops/schedule_work_task` (351) and endpoints 538, 560, 583, 543, 542, 545, 541. Copilot OFF: its columns 52/55 refused on every path; a person's column passes; copilot ON: 200. 583's 200 path not re-proven (all test cards already scheduled). PATCH 545 omitting fields kept title/assignee/duration/status. Refusals logged (events 9240-9257).
- All pushes: no logic drift found; 538/545/541 descriptions refreshed from the repo. Copilot back ON; scratch 365/366 deleted.
- Gaps: 542 with a copilot's day but no override is not checked; 543 ignores a task's existing override.
- Test rows: timelines 60, 61; planner tasks 134, 135, 136 (steps 868, 870 now scheduled).
## Handoff 4-B - four copilot planner tools (2026-11-16, helper agent, checked by Opus 5.5)
- Shared rules copied from the live endpoints: `planner_ops/unschedule_step` 367 (576), `set_start_override` 368 (617), `set_time_window` 369 (613), `schedule_card` 370 (583, keeps the E-COP-059 guard).
- Tools (R1 shape, `plan_draft`): `plan_unschedule_step` 178 (draft days only), `plan_set_start_time` 179, `plan_set_time_window` 180 (date read-back), `plan_schedule_card` 181 (assignee always 0, capacity warning). Agent 40 now has 37 tools.
- debugTool as the copilot: each one success + refusals (E-SCHED-009/010/001, E-TW-002, "date does not exist", E-COP-055 on published day 53, not found).
- Found: live endpoint 576 says "this card" where its repo file and the catalog say "this step" (existing drift, not touched).
- Not done: `tests/cop5_tool_vs_endpoint.py` not extended; time window on a live job and E-COP-059 via schedule_card not exercised. Each rule now exists twice until 4-C.
- Test rows (plan 47): slot 133 removed, slot 137 holds 873+874; a time window for job 147; a start override row left orphaned on slot 133.
- `npm test` 879/879, tsc clean.
- R10 not changed: capacity 0 = 8 and duration 0 = "use expected" (both are written in the tool instructions for the AI); writing the slot before the capacity warning.

## Finishing the initiative (2026-11-16, Opus 5.5) - founder: "update the epics and continue until this AI copilot initiative is complete"
- **Epic status lines** brought up to date (COP-1, 2, 3, 5, SEC-3 were stale since 15 Nov).
- **COP-6 story 02** logins encrypted in Xano - done; keyed run 12/12 (see EPIC-COP-6).
- **SEC-3 05/06** refusals logged max 5 per reason per hour (16 calls -> 5 rows); nightly door check inside task 19 (plan allows 10 tasks, all used). Live: `state: shut`.
- **R8** `record_my_task_event` (170) now asks the frozen publication, like `list_my_tasks`. Live: own task 866 note recorded; task 873 (draft day) refused.
- **R15** run function (353): a refused lock that lost to a run which just ended is now a skip, not a red failure; "could not start" has its own code **E-COP-070** (GUARD-REG-01 refused reusing 057); refused calls counted for this business (or calls naming none) only. Real AI run 30 finished cleanly after the push. Not done: storing the run id on each tool-call row (needs a table change - ask first).
- **633** copilot create: reads the caught error safely, logs the database's words to the event log (E-COP-007), shows only the plain sentence. Live: second copilot -> E-COP-006.
- **COP-1 04 Health view** "AI tool calls" panel (endpoint 660, function 379).
- **COP-2 04 Undo** endpoint 661: a saved note is really undone; work updates say where to change them. Probe 4/4, browser Undo worked.
- **COP-5 01 live-day changes** wait for approval (`plan_live_change`, function 380, tools 176/179/180/181). Full cycle proven (item 29 waiting -> approved -> executed). Test leftover: start override 09:30 on slot 127 (live day 53), 10:00 on slot 137.
- **COP-4 05 "my edits teach it"** tool 182 on agent 40. Proven with planted rows (deleted).
- **R11** `cop5_tool_vs_endpoint.py` now asserts and exits 1 on drift (9/9); COP-7's missing probe script corrected in its epic.
- **Playwright, first full run (2026-11-16, port 3011, test admin usr2-q, account 13):** 47 tests - **5 passed, 37 failed, 5 skipped** (21 min). Read through: the failures are stale specs, not copilot regressions - text the redesigned (new-ui) screens no longer show ("AI Interviewer", `dayboard-job-provenance`), fixed map 219 from another test account (accept-map refused), and a "Done" locator that also matched job rows ("· 0 of 2 steps done"). Fixed that locator (`exact: true`, 2 specs); re-run of the 3 planner specs: 3 passed, 3 still fail on the missing provenance label while the screenshot shows the card correctly on the day. No spec covers the copilot screens. **Rewriting the stale specs for new-ui is its own task.** Specs left test jobs in plan 47 ("E2E card/job/board ...").
- **workflow_tests:** still not run - no tool can run a workflow test from a session (CLAUDE.md).
