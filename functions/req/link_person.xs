// REQ-1 story 03 — THE one place a person on a plan is tied to their lasting profile. WRITE-ONLY helper: it does not check tenancy or admin rights, the CALLER does (the planner agent is in the caller's plan, the profile is in the caller's account via planner/assert_agent_profile). The link is one row per person on a plan (unique on planner_agent_id): linking again to the SAME profile changes nothing, to another profile replaces it (delete and add: the table is append-only). `how` says where it came from: template | picked | repeat | fill | hand | created. Safe to re-run, safe inside the caller's transaction (a write-only function.run rolls back with it). Returns whether a row was made, changed or already right. Every input is passed explicitly by callers: an omitted one silently inherits the caller's own input of the same name.
function "req/link_person" {
  input {
    int account_id filters=min:1
    int planner_agent_id filters=min:1
    int agent_profile_id filters=min:1
    text how filters=trim
    int user_id?
  }

  stack {
    db.query planner_agent_profile {
      where = $db.planner_agent_profile.planner_agent_id == $input.planner_agent_id
      return = {type: "single"}
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    var $existing_profile {
      value = $existing|get:"agent_profile_id":0
    }

    var $result {
      value = "created"
    }

    conditional {
      if ($existing_id == 0) {
        db.add planner_agent_profile {
          data = {
            account_id      : $input.account_id
            planner_agent_id: $input.planner_agent_id
            agent_profile_id: $input.agent_profile_id
            linked_how      : $input.how
            linked_by       : $input.user_id
          }
        } as $added
      }

      elseif ($existing_profile != $input.agent_profile_id) {
        // A re-link is a delete and a fresh row, so the table stays append-only (no updated_at needed).
        db.del planner_agent_profile {
          field_name = "id"
          field_value = $existing_id
        }

        db.add planner_agent_profile {
          data = {
            account_id      : $input.account_id
            planner_agent_id: $input.planner_agent_id
            agent_profile_id: $input.agent_profile_id
            linked_how      : $input.how
            linked_by       : $input.user_id
          }
        } as $replaced

        var.update $result {
          value = "changed"
        }
      }

      else {
        var.update $result {
          value = "same"
        }
      }
    }
  }

  response = {result: $result}
}
