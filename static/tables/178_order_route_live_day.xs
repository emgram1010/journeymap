// DEMAND-1 story 01 (2026-11-21, decision D-11) — the same-day switch for one routing rule. One row per routing rule (route_id unique). agent_id is the plan member whose LIVE day an order dated that day is added to; 0 or no row = off, and the order stays in the backlog. A side table, not a column on order_route, so the rule table is never altered. Default is off: nothing reaches a live day until an admin picks a member.
table order_route_live_day {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    timestamp updated_at?
    int account_id? {
      table = "account"
    }

    int route_id? {
      table = "order_route"
    }

    int agent_id? {
      table = "planner_agent"
    }

    int updated_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "route_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "agent_id", op: "asc"}]}
    {type: "btree", field: [{name: "updated_by_user_id", op: "asc"}]}
  ]
}
