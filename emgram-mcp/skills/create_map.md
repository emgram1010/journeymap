# Skill: Create a Journey Map

## When to use
User describes a new process they want to document or automate.
Always run `search_maps` first to check if a similar map exists.

---

## 🚨 HARD RULE: Every Map Must Live in a Workspace

**Never call `create_journey_map` without a `journey_architecture_id`.**

A map without a workspace is orphaned — invisible to teams, unsearchable by architecture,
and cannot participate in multi-map flows, scenarios, or link_map wiring.

```
1. Ask: "Which workspace should this map live in?"
   OR call list_workspaces to show existing options.
2. If user has an existing workspace → use its id.
3. If no workspace exists or user wants a new one →
   create_workspace { title: "...", description: "..." }
   then use the returned id.
4. Pass journey_architecture_id to create_journey_map — always.
```

No exceptions. A floating map (`journey_architecture = 0`) is a bug, not a choice.

---

## What `create_journey_map` Actually Creates

- **8 default stages**: `s1` through `s8`, labeled "Stage 1" through "Stage 8"
- **1 default lens**: `description` (key: `description`)

Additional lenses must be added via `scaffold_map` in the next step.

---

## Flow: SOP Map

```
1. search_maps         { query: "user's process description" }
2. resolve_workspace   ask user or create_workspace
3. create_journey_map  { title, intent: "sop", journey_architecture_id }
4. scaffold_map        { lens_operations: [
                           { action: "add", label: "Customer",  actor_type: "customer"  },
                           { action: "add", label: "Internal",  actor_type: "internal"  },
                           { action: "add", label: "Metrics",   actor_type: "metrics"   }
                         ]}
5. scaffold_map        { stage_operations: [rename stages with stage_goal + primary_actor_lens] }
6. fill_cells          { cell_updates: [...] }
7. publish_map         (with user confirmation)
```

---

## Flow: Automation Map — Run Intake Interview First

Ask these 3 questions BEFORE calling any tool:
1. "What process are you trying to automate?"
2. "What triggers it — an event, a schedule, or a person doing something?"
3. "What should happen at the end — notify someone, update a system, send a message?"

Then execute:
```
1. search_maps         { query: "...", intent: "automation" }
2. resolve_workspace
3. create_journey_map  { title, intent: "automation", journey_architecture_id }
4. scaffold_map        { lens_operations: [customer, internal, handoff, engineering] }
5. scaffold_map        { stage_operations: [rename s1–sN with stage_goal + primary_actor_lens] }
6. fill_cells          { cell_updates: [handoff cells pre-filled from intake answers] }
7. publish_map         (with user confirmation)
```

---

## ⚠️ Mandatory: Fill Journey Settings After create_journey_map

`create_journey_map` leaves map-level metadata blank. PATCH before filling cells:

```
PATCH /journey_map/{id}
{
  "primary_actor": "...", "journey_scope": "...", "start_point": "...",
  "end_point": "...", "duration": "...", "success_metrics": "...",
  "key_stakeholders": "...", "dependencies": "...",
  "pain_points_summary": "...", "opportunities": "..."
}
```

---

## ⚠️ Mandatory: No Silent Cell Gaps

Every named stage × every lens must have content — even if minimal:
- If an actor doesn't participate in a stage → write "N/A — [actor] does not act at this stage"
- Never leave a cell blank by omission

---

## Status Rules

| Status | Meaning | Can AI overwrite? |
|---|---|---|
| `open` | Never filled (default) | Yes |
| `draft` | AI-written via fill_cells | Yes |
| `confirmed` | User-reviewed and approved | **NO — never** |
| `disabled` | Intentionally off | No |

`fill_cells` always writes `status: "draft"`. It does NOT check existing status — if you call it on a `confirmed` cell it will overwrite it. Always check cell status in `get_map` before writing.
