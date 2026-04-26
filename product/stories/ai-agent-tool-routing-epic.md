# AI Agent Tool Routing — Actor Cell Write Fix

**Epic goal:** The AI agent currently uses `batch_update` for every cell regardless of lens type, writing all content to the `content` field. Actor lens cells (Customer, Driver, Support Agent, etc.) store their data in `actor_fields`, not `content`. The matrix UI reads `actor_fields` for actor rows — so the agent's writes are invisible to the user. This epic fixes the tool routing so the agent uses the correct write tool per lens type, and surfaces `actor_type` in `get_gaps` so the agent can make that decision autonomously.

---

## Root Cause (confirmed via API response log)

`get_gaps` returns gap entries without `actor_type`:
```json
{ "stage_key": "s2", "lens_key": "lens-2", "cell_id": 5749 }
```
The agent has no signal to distinguish actor rows from description rows, so it defaults to `batch_update` for everything. `batch_update` writes to `content`. Actor row tiles in the matrix check `actor_fields`. Result: data written, UI shows "No data yet".

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Surface actor_type in get_gaps | Add `actor_type` and `template_key` to each gap item | Agent needs both to pick the right tool and field set |
| 2 | Tool routing location | Agent system prompt routing rule | No code change needed; prompt controls agent reasoning |
| 3 | Existing `content` written to actor cells | Leave in place; do not backfill | Content field is valid storage; no user-visible harm |
| 4 | Batch size for actor writes | Keep at 8 per call | Matches existing `batch_update` pattern; controls latency |

---

## Vocabulary

| Term | Definition |
|---|---|
| **Actor cell** | A journey cell belonging to a lens with a non-empty `actor_type` (customer, internal, external) |
| **Description cell** | A journey cell on the Description lens (`actor_type` is null or empty string) |
| **Tool routing** | The agent's decision of which write tool to use based on the cell's lens type |
| **Gap** | A cell identified by `get_gaps` as empty or unfilled |

---

## User Stories

### US-ATR-01 — Add `actor_type` and `template_key` to `get_gaps` response
**File:** `tools/9_get_gaps.xs`

Each gap object currently returns `{ stage_key, stage_label, lens_key, lens_label, cell_id }`.

Add two fields to each gap item:
- `actor_type` — value from `$l_rec.actor_type` (e.g. `"customer"`, `"internal"`, `""`)
- `template_key` — value from `$l_rec.template_key` (e.g. `"customer-v1"`, `"internal-v1"`, `""`)

**Acceptance criteria:**
- Description row gaps return `actor_type: ""`, `template_key: ""`
- Customer row gaps return `actor_type: "customer"`, `template_key: "customer-v1"`
- Internal row gaps return `actor_type: "internal"`, `template_key: "internal-v1"`
- All existing gap fields (`stage_key`, `stage_label`, `lens_key`, `lens_label`, `cell_id`) unchanged

---

### US-ATR-02 — Add tool routing rule to agent system prompt
**File:** `agents/2_journey_map_assistant.xs`

Add a routing rule in the system prompt so the agent uses the correct tool per cell type. Place it in the `## Continuation turn rule` section added by AMBC-02.

Rule to add:
```
## Tool routing rule — actor cells vs description cells
When filling cells, always check the `actor_type` field on each gap before choosing a tool:

- If `actor_type` is null or "" (Description row) → use `batch_update` with the `content` field
- If `actor_type` is "customer" → use `update_actor_cell_fields` with the customer field set
  (entry_trigger, emotions, information_needs, decisions_required, friction_points,
   assumptions, acceptance_criteria, expected_output, channel_touchpoint)
- If `actor_type` is "internal" → use `update_actor_cell_fields` with the internal field set
  (task_objective, entry_trigger, tools_systems, information_needs, decisions_required,
   friction_points, assumptions, handoff_dependencies, success_criteria,
   output_deliverable, employee_constraints, pain_points)

Never use `batch_update` on actor cells. Never use `update_actor_cell_fields` on Description cells.
Group actor cells by lens and process one lens at a time to stay within step budget.
```

**Acceptance criteria:**
- Agent calls `update_actor_cell_fields` (not `batch_update`) when gap has `actor_type` != ""
- Agent calls `batch_update` (not `update_actor_cell_fields`) when gap has `actor_type` == ""
- Tool trace confirms correct tool per row type

---

### US-ATR-03 — Update `get_gaps` empty-check to align with write tools
**File:** `tools/9_get_gaps.xs`

Following the tool routing fix, the gap detection logic must match what each tool writes:
- Description cells → gap when `content` is null or `""` (existing — confirmed correct)
- Actor cells → gap when `actor_fields` is null, `{}`, or all values are null/empty (BUG-06 fix — already implemented)

No new code change needed here — this story is a verification gate. Confirm via API call that `get_gaps` returns 0 after a correctly routed build run.

**Acceptance criteria:**
- After a full build using correct tool routing, `get_gaps` returns `total_gaps: 0`
- Actor cells with at least one filled `actor_fields` value are NOT listed as gaps
- Description cells with non-empty `content` are NOT listed as gaps
