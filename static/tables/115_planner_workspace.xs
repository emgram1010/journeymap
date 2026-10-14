// PLN-1 (US-PLN-1-02) — A planning workspace ("plan"): the container every
// agent, timeline and task belongs to.
//
// Amended in this first push by phase-4's P3A-1 (US-P3A-1-01): `is_archived`
// and `plan_template_id`. P3A-1 exists so phase-3 lands history-safe the
// first time instead of needing a second migration.
table planner_workspace {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
      description = "Tenancy root."
    }

    int created_by? {
      table = "user"
    }

    text name? filters=trim {
      description = "Required by the API (PLN-3). Unique within an account."
    }

    date planning_window_start?

    date planning_window_end? {
      description = "Must be >= planning_window_start. API-enforced (PLN-3)."
    }

    int input_tokens_per_minute?=2000

    int output_tokens_per_minute?=500

    bool is_archived?=false {
      description = "P3A-1: a plan with recorded work is archived, never deleted. Archived plans are hidden from default lists and read-only."
    }

    int plan_template_id? {
      description = "P3A-1: the plan template this workspace came from. DELIBERATELY NOT a declared reference — plan_template is PLAN-1's table and does not exist yet, and adding the reference later would mean updateTableSchema, which silently drops this table's trim validators. PLAN-1's endpoints enforce it. 0 = none."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}, {name: "name", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "created_by", op: "asc"}]}
  ]
}
