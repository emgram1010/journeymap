// PLAN-1 (US-PLAN-1-01) — A reusable shape for a plan: how long its
// window runs, what time days start, and which published maps it
// accepts.
//
// DELIBERATELY TINY. No tasks, no people, no roles, no capacity
// (PLAN-1 Non-Goals). Tasks are generated per job from a published map
// version (JOB-1), never copied from a template — a template that
// carried work would quietly go stale the moment the map changed.
//
// An instance created from this template is a COPY. Editing the
// template afterwards never reaches a plan already created from it,
// which is what makes it safe to tidy a template mid-quarter.
//
// Archived, never deleted: instances reference it, and the history of
// how a plan was set up should outlive the template.
//
// Live id 119, not the 83 the epic reserved — Xano assigns table ids
// and ignores what a plan asks for (see product/learning-fixes.md).
table plan_template {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int account_id? {
      table = "account"
    }

    text name? filters=trim {
      description = "Unique within the account. 1-80 characters (API-enforced, PLAN-1)."
    }

    int window_days?=14 {
      description = "Length of the planning window, INCLUSIVE of both ends. 1-366, API-enforced."
    }

    text default_start_time?="08:00" filters=trim {
      description = "HH:MM, 24-hour, two digits each. Copied onto each timeline the instance creates."
    }

    bool is_active?=true {
      description = "False = archived. Archived templates are hidden from the picker; existing instances are unaffected."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree|unique", field: [{name: "account_id", op: "asc"}, {name: "name", op: "asc"}]}
  ]
}
