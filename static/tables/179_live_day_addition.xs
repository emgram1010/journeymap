// DEMAND-1 story 01 (2026-11-21, decision D-11) — one row each time a job is added to a day that is already live. Append-only: never updated, never deleted. It says which job, which day, which publication version the add produced, how many blocks and minutes it added, who or what asked (origin: order or person) and when. It is the record that this work was NOT part of the plan (unplanned), and the count per day that caps a flood (50 a day).
table live_day_addition {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int timeline_id? {
      table = "planner_timeline"
    }

    int work_item_id? {
      table = "work_item"
    }

    int plan_publication_id? {
      table = "plan_publication"
    }

    int from_version?
    int to_version?
    int item_count?
    int added_minutes?
    text origin?
    int added_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "timeline_id", op: "asc"}]}
    {type: "btree", field: [{name: "work_item_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "plan_publication_id", op: "asc"}]}
    {type: "btree", field: [{name: "added_by_user_id", op: "asc"}]}
  ]
}
