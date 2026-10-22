// PLAN-2 (US-PLAN-2-01) — A durable, per-person "agent profile",
// independent of any one plan.
//
// WHY THIS TABLE EXISTS: `planner_agent` only ever exists INSIDE a
// single `planner_workspace` (unique per workspace+name, created fresh
// by hand every time a plan is built). There is no identity for a
// person-as-agent that survives across plans. This table is that
// identity — just enough to seed a fresh `planner_agent` row wherever
// the person is added, nothing about a specific plan, nothing about
// scheduling (deferred, see the epic's Non-Goals).
//
// NO UNIQUE INDEX ON `user_id`, deliberately — same reasoning
// `planner_agent`'s own header already documents: an int column here
// cannot hold a real null, it defaults to 0, and every AI profile
// (which has no login) would share that same 0. A unique index would
// reject every second AI profile. "At most one profile per real user"
// is enforced by the API with a count check instead (PLAN-2's own
// create endpoint), exactly like `plan_template` enforces its unique
// name without a DB-level unique constraint on it either.
//
// `account_id` is required ONLY for an AI profile (user_id = 0), which
// has no `user` row to inherit tenancy through. A person profile's
// tenancy is read via `user.account_id` at query time instead.
table agent_profile {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    date updated_at?

    int user_id? {
      table = "user"
      description = "0 = an AI profile with no login. A person profile's tenancy is read through this user's account_id, not stored here."
    }

    int account_id? {
      table = "account"
      description = "Required only when user_id = 0 (an AI profile) -- there is no user row to inherit tenancy from otherwise."
    }

    enum kind? {
      values = ["person", "ai"]
      description = "Required by the API (PLAN-2)."
    }

    text name? filters=trim {
      description = "Required when user_id = 0 (an AI agent names itself here, same as planner_agent does today). For a person, display name comes from user.name at read time."
    }

    text color? filters=trim {
      description = "Hex, e.g. #4f46e5. Display default only."
    }

    decimal default_daily_capacity_hours?=8

    bool is_eligible?=true {
      description = "The \"tagged as an agent\" flag. Turning it off hides the profile from future template rosters without deleting history on plans they're already on."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "user_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "is_eligible", op: "asc"}]}
  ]
}
