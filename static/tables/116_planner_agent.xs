// PLN-1 (US-PLN-1-03) — Who (or what) does the work in a plan: a person or
// an AI agent.
//
// Amended in this first push by phase-4's P3A-1 (US-P3A-1-01): `user_id`
// and `is_active`. `user_id` moved here from APP-1 to remove a circular
// dependency with LIVE-1.
//
// Two rules the schema deliberately does NOT enforce:
//   - `model_id` only applies to kind = "ai" (PLN-5 rejects it on a person).
//   - one login per agent per plan. US-P3A-1-01 asked for a unique index on
//     (workspace_id, user_id), but an int column here cannot hold a real
//     null — it defaults to 0 — so that index would reject every second
//     agent that has no login yet. PLN-5/APP-1 enforce it instead.
table planner_agent {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int workspace_id? {
      table = "planner_workspace"
    }

    text name? filters=trim {
      description = "Required by the API (PLN-5). Unique within a workspace."
    }

    enum kind? {
      values = ["person", "ai"]
      description = "Required by the API (PLN-5)."
    }

    text color? filters=trim {
      description = "Hex, e.g. #4f46e5. Display only."
    }

    decimal daily_capacity_hours?=8

    bool is_visible?=true

    int model_id? {
      table = "planner_model"
      description = "AI agents only — the API rejects a model on a person agent (PLN-5). 0 = none."
    }

    int user_id? {
      table = "user"
      description = "P3A-1: the login that performs this agent's work. 0 = no login yet. One login per agent per plan is API-enforced, NOT a unique index: an int column here cannot hold a real null (it defaults to 0), so a unique index would reject every second agent that has no login."
    }

    bool is_active?=true {
      description = "P3A-1: an agent with recorded work is deactivated, never deleted. Inactive agents are hidden from the roster and from new assignments; their history stays intact."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "workspace_id", op: "asc"}, {name: "name", op: "asc"}]}
    {type: "btree", field: [{name: "workspace_id", op: "asc"}, {name: "is_visible", op: "asc"}]}
    {type: "btree", field: [{name: "model_id", op: "asc"}]}
    {type: "btree", field: [{name: "user_id", op: "asc"}]}
  ]
}
