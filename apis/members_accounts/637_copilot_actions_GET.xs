// COP-2 stories 03/04 — the Approvals inbox for the signed-in admin's account: everything the
// copilot is waiting on ("waiting"), and what it did or what was decided ("done": told, seen,
// approved, edited, executed, rejected, expired, failed). Runs expiry for this account first, so
// an item older than 72 hours is never shown as approvable even if the hourly task is late.
//
// Account admins only (usr/assert_team_admin); account_id comes from the admin's own record,
// never an input. The payload is returned here — this is the one place the owner sees exactly
// what the copilot wants to send or write.
query "copilot/actions" verb=GET {
  api_group = "Members & Accounts"
  auth = "user"

  input {
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/actions"
        entity_id    : 0
      }
    } as $admin_user

    function.run "copilot/expire_waiting" {
      input = {account_id: $admin_user.account_id}
    } as $_expiry

    db.query copilot_action {
      where = $db.copilot_action.account_id == $admin_user.account_id && $db.copilot_action.status == "waiting"
      sort = {created_at: "desc"}
      return = {type: "list"}
    } as $waiting

    db.query copilot_action {
      where = $db.copilot_action.account_id == $admin_user.account_id && $db.copilot_action.status != "waiting"
      sort = {updated_at: "desc"}
      return = {type: "list"}
    } as $done

    db.query copilot_action {
      where = $db.copilot_action.account_id == $admin_user.account_id && $db.copilot_action.status == "told"
      return = {type: "count"}
    } as $unseen
  }

  response = {
    waiting      : $waiting
    done         : $done
    waiting_count: $waiting|count
    unseen_count : $unseen
  }
  tags = ["cop-2"]
}
