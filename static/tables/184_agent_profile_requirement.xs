// REQ-1 (US-REQ-1-02) — what a person holds: one row per (lasting profile, requirement). It sits on the lasting profile (agent_profile), never on a plan, so a plan that is repeated does not copy stale answers. held_until is TEXT "YYYY-MM-DD" or "" on purpose: an empty value means no end (0, "" and null all compare equal in this engine, so the rule is "ends only when a real date is present"), a text date compares correctly against a plan date, and an optional date input that is left out does not exist at all. The last day counts: a holding until 2027-03-31 is held on 2027-03-31 and not on 2027-04-01. Compared to the DATE OF THE WORK, never to a clock. Saving twice updates this row. A removal deletes the row and writes who and when to the event log. Switching a person off keeps their holdings (history).
// NOT PUSHED until the founder says yes. New table; no existing table is changed.
table agent_profile_requirement {
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

    int agent_profile_id? {
      table = "agent_profile"
    }

    int requirement_id? {
      table = "requirement"
    }

    text held_until? {
      description = "YYYY-MM-DD, or empty for no end."
    }

    int recorded_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "agent_profile_id", op: "asc"}, {name: "requirement_id", op: "asc"}]}
    {type: "btree", field: [{name: "requirement_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
    {type: "btree", field: [{name: "recorded_by", op: "asc"}]}
  ]
}
