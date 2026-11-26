// REQ-1 (US-REQ-1-03) — ties a person ON A PLAN (planner_agent, a fresh row in every plan) to their lasting profile (agent_profile), so what they hold and when they work follows them into every plan. A side table, not a column: planner_agent has text validators, and changing it would drop them (CLAUDE.md, updateTableSchema). Unique on the person on a plan: one link each. linked_how says where the link came from: template | picked | repeat | fill | hand | created. A name is never matched automatically: a person confirms each one. The row is deleted with the person on the plan or with the profile. Emptying this table changes no existing screen.
// NOT PUSHED until the founder says yes. New table; no existing table is changed.
table planner_agent_profile {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int planner_agent_id? {
      table = "planner_agent"
    }

    int agent_profile_id? {
      table = "agent_profile"
    }

    text linked_how? {
      description = "template | picked | repeat | fill | hand | created"
    }

    int linked_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "planner_agent_id", op: "asc"}]}
    {type: "btree", field: [{name: "agent_profile_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "linked_by", op: "asc"}]}
  ]
}
