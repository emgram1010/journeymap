# Skill: Map Invocation & Execution Health

## When to use
- An `ai_agent` actor on a map has `agent_map_id` set → use `invoke_map` to run it
- User asks "how is X map performing" or "why is stage Y failing" → use execution_health endpoint
- Orchestrator needs to delegate a stage to a sub-agent map → use `invoke_map`

---

## invoke_map

**Tool:** `invoke_map` (in `ai/tool/invoke_map.xs`)
**Also available as:** `POST /journey_map/{map_id}/invoke` (HTTP endpoint)

### When the Orchestrator calls this
When executing a stage and the `ai_agent` lens has `agent_map_id` set:
1. The Orchestrator delegates instead of generating text
2. Passes current stage context as `input_data`
3. Waits for sub-execution to complete
4. Uses `final_output` as the actor's stage contribution

### Input

```json
{
  "target_map_id": 88,
  "input_data": { "lead_id": "42", "company": "Acme Corp" },
  "parent_execution_id": 15,
  "subject_label": "Acme Corp",
  "current_map_id": 126
}
```

| Field | Required | Notes |
|---|---|---|
| `target_map_id` | Yes | The `agent_map_id` from the lens |
| `input_data` | No | Current stage context as JSON |
| `parent_execution_id` | No | Links child execution to parent |
| `subject_label` | No | Human-readable subject name |
| `current_map_id` | Yes (for circular guard) | Pass the current map's id |

### Response

```json
{
  "execution_id": 99,
  "status": "completed",
  "final_output": "Sub-agent completed: qualification score 8/10, move to close stage",
  "target_map": 88
}
```

`status` is `"completed"` or `"failed"`. `final_output` is the last message from the Orchestrator run on the target map.

### Circular Guard
`invoke_map` rejects if `target_map_id == current_map_id`. A map cannot invoke itself.

---

## execution_health

**Endpoint:** `GET /journey_map/{journey_map_id}/execution_health`
**Auth:** user (owner only)

Not yet available as an MCP tool — call via HTTP directly.

### Response

```json
{
  "journey_map_id": 126,
  "total_runs": 42,
  "completed_runs": 31,
  "failed_runs": 11,
  "stage_health": [
    {
      "stage_key": "s3",
      "stage_label": "Case Study Followup",
      "failure_rate": 0.42,
      "common_failure_reasons": ["connection_not_accepted", "email_bounced"]
    }
  ]
}
```

### Interpreting Results

- `failure_rate > 0.20` on any stage → flag for improvement
- Suggest fix based on `common_failure_reasons`:
  - `connection_not_accepted` → add exception map that routes to email instead
  - `email_bounced` → add prerequisite_data validation for `subject_email`
  - `linkedin_rate_limit` → add wait stage before outreach
