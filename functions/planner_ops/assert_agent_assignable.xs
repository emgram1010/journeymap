// Handoff 4-A rule 2 (COP-5 story 06) - THE one server check for "may new work land on this plan column?". A column (planner_agent) linked to an AI identity that is switched off (user_status.is_active == false) is refused (E-COP-059, the same sentence as the planner screen's COPILOT_OFF_MESSAGE) and the refusal is logged as a rejected event. A person's column, an unlinked column, an active copilot and agent_id 0 (no column named) all pass untouched - this never throws for them.
function "planner_ops/assert_agent_assignable" {
  input {
    int agent_id?
    int actor_user_id?
    int account_id?
    text step? filters=trim
  }

  stack {
    db.query planner_agent {
      where = $db.planner_agent.id == $input.agent_id && $input.agent_id != 0
      return = {type: "single"}
      output = ["id", "user_id"]
    } as $agent

    var $linked_user {
      value = ($agent|get:"user_id":0) ?? 0
    }

    db.query ai_identity {
      where = $db.ai_identity.user_id == $linked_user && $linked_user != 0
      return = {type: "count"}
    } as $ai_rows

    db.query user_status {
      where = $db.user_status.user_id == $linked_user && $linked_user != 0
      return = {type: "single"}
      output = ["id", "is_active"]
    } as $status

    // Absence of a user_status row means active (USR-1). Read as == false, never as a null test.
    var $switched_off {
      value = ($linked_user != 0) && ($ai_rows > 0) && (($status|get:"is_active":true) == false)
    }

    conditional {
      if ($switched_off == true) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-5"
            step       : $input.step
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-COP-059"
            message    : "New work was refused for a switched-off copilot's column."
            user_id    : $input.actor_user_id
            account_id : $input.account_id
            entity_type: "planner_agent"
            entity_id  : $input.agent_id
            metadata   : {}
          }
        } as $_refused_logged
      }
    }

    precondition ($switched_off == false) {
      error_type = "inputerror"
      error = "The copilot is switched off, so it can't be given new work. An admin can switch it back on in Manage users, or pick someone else. (E-COP-059)"
    }
  }

  response = {ok: true}
}
