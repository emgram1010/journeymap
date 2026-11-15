// COP-4 stories 02/04 (2026-11-15) — what KIND of map this is, how it was made, and where its
// facts came from. One row per map, written by the copilot (kind, made_by, sources, research note)
// or the owner. "Tested" (tested_since) is set only by the owner or completed work, never by the
// copilot (E-COP-046). A map with no row shows no label and no warning (behaves as today).
// Side table with its own GET endpoint, merged in the frontend; no column on journey_map.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed;
// S6 unique natural key (journey_map_id).
table copilot_map_profile {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?

    int journey_map_id? {
      table = "journey_map"
    }

    int account_id? {
      table = "account"
    }

    int journey_architecture_id? {
      table = "journey_architecture"
    }

    enum kind? {
      values = ["insight", "runnable"]
      description = "insight = knowledge/strategy to read; runnable = a process to plan and run from."
    }

    enum made_by? {
      values = ["person", "copilot_research", "copilot_strategy", "copilot_draft"]
    }

    json sources? {
      description = "Pages the map drew on: [{title, url}]. Never long passages."
    }

    text research_note? filters=trim {
      description = "What is general practice, what was fitted to this business, what was thin or conflicting."
    }

    timestamp tested_since? {
      description = "Set when real work proved it (by the owner or completed work). Empty = researched, not tested."
    }

    int updated_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "journey_map_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by_user_id", op: "asc"}]}
  ]
}
