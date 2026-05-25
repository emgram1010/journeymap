# Skill: Query a Journey Map

## When to use
User wants to see an existing map, find maps on a topic, or understand what's in a map.

---

## Tool Selection Guide

| Signal | Tool |
|---|---|
| "show me all maps", "what maps do we have" | `list_maps` |
| "do we have a map for X", "find maps about Y" | `search_maps` |
| User gives a map name or topic | `search_maps` → then `get_map` |
| User gives a map ID directly | `get_map` |
| "show me stage 2 of X", "what's in the handoff row" | `get_map` → read stage/lens |

---

## Orientation Pattern (new session)

At the start of every new session, orient yourself:
```
1. list_maps → understand what exists
2. If user references something specific → search_maps
3. Load full state with get_map before making any edits
```

Never assume what's in a map. Always read before writing.

---

## Flow: Find Map by Topic

```
1. search_maps { query: "linkedin outreach", intent: "automation" }
2. Review returned ai_summary fields to find best match
3. get_map { journey_map_id: <matched id> }
4. Report findings to user
```

---

## What get_map Returns (Actual Schema)

```json
{
  "journey_map": {
    "id": 126,
    "title": "LinkedIn Prospect Outreach",
    "status": "active",
    "intent": "automation",
    "ai_summary": "Process: Automated outreach to LinkedIn prospects..."
  },
  "stages": [
    { "id": 1, "key": "s1", "label": "Send Connection Request", "display_order": 1 }
  ],
  "lenses": [
    { "id": 10, "key": "lens-2", "label": "Handoff", "actor_type": "handoff" }
  ],
  "cells": [
    {
      "id": 55,
      "stage_key": "s1",
      "lens_key": "lens-2",
      "actor_type": "handoff",
      "actor_fields": { "trigger_event": "manual_trigger" },
      "content": "Send LinkedIn connection request to prospect",
      "status": "draft",
      "is_locked": false
    }
  ],
  "summary": {
    "total_cells": 16,
    "filled_cells": 10,
    "empty_cells": 6
  }
}
```

Key fields: `summary.empty_cells` shows gaps at a glance. `cells[].status` = `open`, `draft`, or `confirmed`.
`cells[].id` is the `source_cell_id` to use when calling `link_map`.

---

## What search_maps Returns (Actual Schema)

```json
{
  "query": "linkedin outreach",
  "count": 1,
  "results": [
    {
      "map_id": 126,
      "title": "LinkedIn Prospect Outreach",
      "ai_summary": "Process: Automated outreach...",
      "intent": "automation",
      "tags": ["linkedin", "outreach", "sales"]
    }
  ]
}
```

**Important:** `search_maps` only returns maps with `status == "active"` (published).
Draft maps are invisible to search — use `list_maps` to find drafts.
