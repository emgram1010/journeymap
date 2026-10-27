// CAT-1 — Tenancy guard for a single item_type id.
//
// TWO SEPARATE QUESTIONS, TWO SEPARATE ANSWERS — deliberately NOT
// folded into one notfound the way most other tenancy guards in this
// repo do it (e.g. planner/assert_agent_profile). The epic's own
// acceptance criteria (FT-CAT-1-05) require a cross-account WRITE to
// come back 403 with E-CAT-006 ("You can't change another account's
// catalog") AND a logged `rejected` event -- which means the log has to
// happen HERE, right before the throw, because a failed precondition
// unwinds the whole call stack and the calling endpoint never resumes
// to log it itself.
//   1. Does the row exist at all, in ANY account? No -> notfound (a
//      stale or made-up id; nothing meaningful to disclose or log with
//      a catalog code).
//   2. Does it belong to the CALLER's account? No -> log `rejected`
//      with E-CAT-006, then accessdenied (it exists; the caller just
//      isn't allowed to touch it).
//
// `step` names the calling endpoint's own step (e.g. "update_item_type",
// "deactivate_item_type", "delete_item_type") so the logged event reads
// the same as if the endpoint had logged it itself.
function "catalog/assert_item_type" {
  input {
    int account_id filters=min:1
    int item_type_id filters=min:1
    int user_id filters=min:1
    text step filters=trim
    text correlation_id? filters=trim
  }

  stack {
    db.get item_type {
      field_name = "id"
      field_value = $input.item_type_id
    } as $item

    precondition ($item != null) {
      error_type = "notfound"
      error = "Item type not found"
    }

    conditional {
      if ($item.account_id != $input.account_id) {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : $input.step
            outcome       : "rejected"
            severity      : "warn"
            user_id       : $input.user_id
            account_id    : $input.account_id
            entity_type   : "item_type"
            entity_id     : $input.item_type_id
            correlation_id: $input.correlation_id
            error_code    : "E-CAT-006"
            message       : "Cross-account access refused."
          }
        }
      }
    }

    precondition ($item.account_id == $input.account_id) {
      error_type = "accessdenied"
      error = "You can't change another account's catalog. (E-CAT-006)"
    }
  }

  response = {item: $item}
}
