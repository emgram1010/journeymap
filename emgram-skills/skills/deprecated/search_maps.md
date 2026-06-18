# Skill: Search Maps

## When to use
- User asks if a map exists for a topic
- Before creating a new map (always check first)
- User wants to find maps matching a process, domain, or intent

---

## The Search-First Rule

**Always search before create.**

```
search_maps { query: "user's description" }
  → found → get_map → work with existing
  → not found → offer to create
```

This prevents duplicate maps and keeps the account clean.

---

## Flow: Topic Search

```
1. search_maps {
     query: "linkedin outreach automation",
     intent: "automation"   ← optional filter
   }
2. Review ai_summary of each result to find the right match
3. get_map on best match if relevant
4. Report to user: "Found [N] maps. Closest match: [title] — [ai_summary preview]"
```

---

## Flow: Pre-Create Check

```
User: "I want to build a map for customer onboarding"

1. search_maps { query: "customer onboarding" }
2. If results:
   → "You already have [title]. Want to update it or create a separate one?"
3. If no results:
   → proceed with create_map skill
```

---

## Query Writing Tips

Write queries the way you'd describe the process in plain language:
- "automate linkedin connection and followup messages"
- "onboarding new employees HR"
- "customer support ticket escalation"
- "invoice approval finance workflow"

The `ai_summary` field is structured text — match against process description, actor, domain, triggers, outcome.

---

## Filters Available

| Filter | Values | Use When |
|---|---|---|
| `intent` | sop, automation, hybrid | User specifies purpose |
| `tags` | array of strings | User mentions specific domain tags |

Both are optional. Query alone is enough for most searches.

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

**Critical:** `search_maps` only returns maps with `status == "active"`. Draft maps are invisible. Use `list_maps` to find drafts.

Read `ai_summary` fully before deciding if it's the right map. Title alone can be misleading.

---

## search_maps is Live

Tool is fully implemented (Epic IL-0 + IL-1 complete). No fallback needed.

Maps published before Epic IL-1 went live may have `ai_summary: null`. In that case, fall back to `list_maps` + title scan + `get_map` to inspect manually.
