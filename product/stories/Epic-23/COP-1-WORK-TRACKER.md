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
