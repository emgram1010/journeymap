# Skill: Publish a Journey Map

## When to use
User says "publish", "make it live", "go live", "push to n8n", or after completing a create/update flow.

---

## Flow

```
1. Confirm with user: "Ready to publish map [title]?"
2. publish_map { journey_map_id }
3. Returns:
   - journey_map_id
   - version (integer — increments on each publish)
   - snapshot (full snapshot record)
   - map (updated journey_map record with status: "active")
4. Report back: "Published v{version}. Map is now active."
```

---

## What Happens at Publish (Automatic — No Extra Calls Needed)

| What | Result |
|---|---|
| Map status | Set to `"active"` |
| Snapshot compiled | `{ map_id, map_title, version, compiled_at, stages }` written to `automation_snapshot` |
| Version incremented | New version = previous version + 1 (starts at 1) |
| `ai_summary` generated | One LLM call (claude-haiku-4-5) writes structured summary to `journey_map.ai_summary` |
| ai_summary failure | **Non-fatal** — publish succeeds even if LLM call fails |

**Note:** Webhook push to connected `automation_connection` URLs is handled by the HTTP publish endpoint (`POST /journey_map/{id}/publish`), not the MCP tool directly. If n8n webhook push is needed, verify the map has a registered `automation_connection`.

---

## Actual Response Shape

```json
{
  "journey_map_id": 126,
  "version": 3,
  "snapshot": {
    "id": 45,
    "journey_map": 126,
    "version": 3,
    "compiled_at": "2026-05-24T...",
    "graph": { "map_id": 126, "map_title": "...", "version": 3, "stages": [] }
  },
  "map": { "id": 126, "title": "...", "status": "active", "intent": "automation" }
}
```

---

## When NOT to Publish Immediately

- Map has empty handoff cells and intent = automation → fill gaps first
- User said "draft" or "save for now" → skip publish
- Map has no confirmed automation configs and intent = automation → suggest Config Wizard first

---

## After link_map — Re-publish Required

After calling `link_map`, you MUST re-publish the **source** map:
```
publish_map { journey_map_id: source_map_id }
```
The link alone does not update the automation snapshot. The snapshot compiler reads
`journey_link` records at publish time to build the full linked-map graph.

---

## After clone_scenario — Publish Before compare_scenarios

After modifying a cloned map, publish it before comparing:
```
publish_map { journey_map_id: clone_id }
```
Unpublished maps have no `ai_summary` and incomplete scorecard data.
`compare_scenarios` will return `null` metrics for unpublished maps — never infer a winner from nulls.

---

## After Publish — Check These

For automation maps:
1. Call `get_map` → confirm `journey_map.status == "active"` and `ai_summary` populated
2. n8n Executions tab → did the webhook fire?
3. If n8n not receiving → check `automation_connection` registration and ngrok tunnel status
