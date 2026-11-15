// COP-2 stories 02/04/06 (2026-11-15) — one row per copilot action that the owner needs to see:
// a WAITING action (stored, not done, until the owner decides) or a TOLD action ("runs, then
// tells you": done, then listed under "What the copilot did").
//
// A waiting row holds the tool and its full input exactly as the copilot asked (`payload`), so the
// owner approves exactly what they saw. The copilot's own call only creates the row; the action
// runs only when the copilot re-calls the tool with `approval_id`, and the gate lets it through
// once (copilot_action_claim) and only if the input matches what was approved.
//
// History: never deleted (src/ops/historyTables.ts). Statuses move forward only:
//   waiting → approved | edited | rejected | expired;  approved | edited → executed | failed
//   told (ran) → seen
//
// `payload` can contain customer text. It is shown to the owner on Approvals and to nobody else;
// it never goes to event_log or tool_call_log.
//
// GOV-1: S1 primary key; S2 created_at + updated_at; S3 references declared and indexed.
table copilot_action {
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

    int journey_architecture_id? {
      table = "journey_architecture"
      description = "The business. 0 = a map outside any business."
    }

    int journey_map_id? {
      table = "journey_map"
      description = "The map the action targets, when it has one."
    }

    int requested_by_user_id? {
      table = "user"
      description = "The AI identity that asked."
    }

    text action_type? filters=trim

    text tool? filters=trim

    json payload? {
      description = "The tool input exactly as the copilot sent it."
    }

    json approved_payload? {
      description = "What the owner approved: the payload, or their edited version."
    }

    text summary? filters=trim {
      description = "One line for the screen: what it will do, for whom."
    }

    int amount? {
      description = "Money amount for money types (whole currency units). 0 = none."
    }

    enum status? {
      values = ["waiting", "approved", "edited", "rejected", "expired", "executed", "failed", "told", "seen"]
    }

    text reason? filters=trim {
      description = "Why it is waiting, in plain words."
    }

    int stale_marker? {
      description = "The newest write on the target map when drafted (a tool_call_log id). A newer write means out of date."
    }

    int decided_by_user_id? {
      table = "user"
    }

    timestamp decided_at?

    timestamp executed_at?

    timestamp reminded_at?

    bool reversible? {
      description = "Copied from the action type: can it be undone?"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "status", op: "asc"}]}
    {type: "btree", field: [{name: "journey_architecture_id", op: "asc"}]}
    {type: "btree", field: [{name: "journey_map_id", op: "asc"}]}
    {type: "btree", field: [{name: "requested_by_user_id", op: "asc"}]}
    {type: "btree", field: [{name: "decided_by_user_id", op: "asc"}]}
    {type: "btree", field: [{name: "status", op: "asc"}, {name: "created_at", op: "asc"}]}
  ]
}
