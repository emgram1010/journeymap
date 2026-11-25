// REPEAT-1 (US-REPEAT-1-02) — one row per repeat of a plan: which plan it came from, which plan it
// made, how many days everything moved, who did it, and what was left out.
//
// DRAFT, NOT PUSHED. Waiting for the founder's yes (CLAUDE.md: ask before any schema push).
//
// WHY A NEW TABLE, NOT A COLUMN ON `planner_workspace`: changes to existing tables are
// additive-only, and `updateTableSchema` silently drops trim validators (planner_workspace.name
// has trim). The same side-table move as GOV-1/STAGE-1/TW-1.
//
// THE RACE GUARD IS THE UNIQUE INDEX on (source_workspace_id, new_start_date). Two confirms for
// the same source and start date at the same moment: both try to insert this row inside their
// transaction, the database refuses the second, and its whole transaction rolls back (EXC-1: a
// "does it exist?" read does not stop a true overlap; a unique index does).
//
// `source_workspace_id` IS A PLAIN INT, NOT A REFERENCE: the history link must never block
// anything that happens to the source plan later (story 02, delete behaviour).
//
// STATE: story 00 measured one transaction holding 550 rows in 5.9 s, so a repeat is one
// all-or-nothing write and is written straight as `ready`. `building` is reserved for the staged
// fallback (plans above ~150 jobs); `failed` is never stored (a failed write leaves no row) and is
// recorded in event_log instead.
table plan_repeat {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int source_workspace_id? {
      description = "The plan that was repeated. Plain int on purpose: never a blocker on the source."
    }

    int new_workspace_id? {
      table = "planner_workspace"
      description = "The plan the repeat made. Unique: a plan is made by at most one repeat."
    }

    date new_start_date? {
      description = "With source_workspace_id, the race guard (unique)."
    }

    int shift_days? {
      description = "How many days every date moved."
    }

    enum state?=ready {
      values = ["building", "ready"]
      description = "ready = complete. building = reserved for the staged fallback; hidden from plan lists."
    }

    json counts? {
      description = "What was copied: people, days, jobs, steps, slots, backlog. Written once, never patched."
    }

    json left_out? {
      description = "What was not copied, each with a reason: [{kind, id, name, reason}]. Written once, never patched."
    }

    int created_by? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree|unique", field: [{name: "source_workspace_id", op: "asc"}, {name: "new_start_date", op: "asc"}]}
    {type: "btree|unique", field: [{name: "new_workspace_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
  ]
}
