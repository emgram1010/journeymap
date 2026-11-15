# COP-1 — parallel work tracker

Live list of who is doing what while COP-1 is closed out. One row per track.
Rule: two tracks never touch the same files. Backend gate/tool files belong to the review track until it reports.

| Track | What | Who / model | Files it owns | Status |
|---|---|---|---|---|
| R | Independent review of COP-1 + SEC-3 (read-only) | Opus 5.5 helper | none (reads only) | ✅ 8 findings; 1–4 confirmed by main |
| A | Team page: copilot shown as "AI", "Create copilot" button, daily-limit control | Sonnet 5.5 helper | `webapp/protype-2/src/team/*`, `src/xano.ts` (copilot calls only), new tests | ✅ built, 7 new tests, npm 796/796; not yet seen in a browser |
| F | Fix the review's confirmed findings | Opus 5.5 (main) | see below | 🟡 written in repo, NOT live — push needs founder OK |
| B | Health page: view of `tool_call_log` (needs one new GET endpoint) | Sonnet 5.5 helper | `src/health/*`, new endpoint file | ⏳ after F (endpoint push) |
| C | Old bug: endpoint 209 + `invoke_map` unwrapped filter | Opus 5.5 (main) | `apis/journey_map/209*`, `ai/tool/invoke_map.xs` | ⏳ after R (in review scope) |
| D | Delete endpoint: count owned maps as "has work" | Opus 5.5 (main) | `apis/members_accounts/20_admin_user_delete_POST.xs` | ⏳ after R (in review scope) |

## Review findings (2026-11-14)
| # | Finding | Severity | Fix (repo) | Live |
|---|---|---|---|---|
| 1 | Workflow-run tools (`get/save_workflow_state`, `export_workflow_output`) accept another account's run id | High | run must belong to the gated map; export gates on the run's own map | ⏳ |
| 2 | `list_maps`/`search_maps`/`list_scenarios` show every map to a caller with account 0 | Medium | `see_all` always false | ⏳ |
| 3 | Admin could change the copilot's email (then sign in as it) or role | Medium | api 19 refuses email change (E-COP-012); api 11 refuses role change (E-COP-013) | ⏳ |
| 4b | `save_workflow_state` took the run owner from input | Low | owner = gate's caller | ⏳ |
| 4a | ~10 tools write `agent_tool_log` with an unchecked `conversation_id` | Low | not yet | — |
| 5 | Ticket not pinned to its map (same account only) | Low | COP-3 pinning (known) | — |
| 6 | Cap fails open if the audit insert fails; some tools count 2 | Low | not yet | — |
| 7 | Health refusal-log limit is global, not per account | Low | not yet | — |
| 8 | Endpoint 209 has no owner check (pre-existing) | Low | with track C | — |

## Waiting on the founder
- OK to push the review fixes live (6 tools + endpoints 11, 19).
- `intent` column on `journey_map`: add by hand in the Xano dashboard (tool drops validators).
- Bulk map change (scaffold): undo everything on any failure, or report each step?

## Log
- 2026-11-14 — R and A started in parallel.
- 2026-11-14 — R and A done. Fixes 1–3, 4b written; live push blocked pending founder OK.
