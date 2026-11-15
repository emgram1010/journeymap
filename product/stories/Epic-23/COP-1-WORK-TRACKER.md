# COP-1 — parallel work tracker

Live list of who is doing what while COP-1 is closed out. One row per track.
Rule: two tracks never touch the same files. Backend gate/tool files belong to the review track until it reports.

| Track | What | Who / model | Files it owns | Status |
|---|---|---|---|---|
| R | Independent review of COP-1 + SEC-3 (read-only) | Opus 5.5 helper | none (reads only) | ✅ 8 findings; 1–4 confirmed by main |
| A | Team page: copilot shown as "AI", "Create copilot" button, daily-limit control | Sonnet 5.5 helper | `webapp/protype-2/src/team/*`, `src/xano.ts` (copilot calls only), new tests | ✅ built, 7 new tests, npm 796/796; not yet seen in a browser |
| F | Fix the review's confirmed findings | Opus 5.5 (main) | see below | ✅ pushed live and checked (founder OK 2026-11-14) |
| B | Health page: view of `tool_call_log` (needs one new GET endpoint) | Sonnet 5.5 helper | `src/health/*`, new endpoint file | ⏳ after F (endpoint push) |
| C | Old bug: endpoint 209 + `invoke_map` unwrapped filter | Opus 5.5 (main) | `apis/journey_map/209*`, `ai/tool/invoke_map.xs` | ⏳ after R (in review scope) |
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
| 8 | Endpoint 209 has no owner check (pre-existing) | Low | with track C | — |

## Waiting on the founder
- Nothing right now.

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
