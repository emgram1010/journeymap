// REQ-1 story 01 — Rename a requirement, or change its description. Admin only. A rename is a LABEL change only: every step that needs it, every person who holds it, and every published version point at the record, so they all show the new name at once. Changing what a requirement MEANS is a new requirement plus an archive (the screen says so). The key is recomputed by req/normalize_name and must stay unique in the account (E-REQ-003). `name` and `description` are each optional: an omitted text field arrives as "", so "was it sent?" is read from the raw body with |has (a name sent empty is refused, E-REQ-001; a description sent empty clears it). Another account's requirement is "not found" (E-REQ-006). Events: requirement.renamed. Every input is passed to function.run explicitly.
query "requirement/{requirement_id}" verb=PATCH {
  api_group = "catalog"
  auth = "user"

  input {
    int requirement_id filters=min:1
    text name? filters=trim
    text description? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "requirement/rename", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "req/assert_requirement" {
      input = {account_id: $actor.account_id, requirement_id: $input.requirement_id}
    } as $guard

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = true
    } as $raw_input

    var $has_name {
      value = ($raw_input|has:"name")
    }

    var $has_desc {
      value = ($raw_input|has:"description")
    }

    var $new_name {
      value = $guard.requirement.name
    }

    var $new_key {
      value = $guard.requirement.name_key
    }

    var $new_desc {
      value = $guard.requirement.description
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    function.run "req/validate_name" {
      input = {name: $input.name}
    } as $v

    conditional {
      if ($has_name == true) {
        var.update $new_name {
          value = $v.name
        }

        var.update $new_key {
          value = $v.key
        }

        conditional {
          if ($v.ok == false) {
            var.update $reject_code {
              value = $v.code
            }

            var.update $reject_msg {
              value = $v.message
            }
          }
        }
      }
    }

    conditional {
      if ($has_desc == true) {
        var.update $new_desc {
          value = $input.description
        }
      }
    }

    var $desc_ok {
      value = (($new_desc|strlen) <= 300) && (("/<[a-zA-Z][^>]*>/"|regex_matches:$new_desc) == false)
    }

    conditional {
      if ($reject_code == "" && $desc_ok == false) {
        var.update $reject_code {
          value = "E-REQ-009"
        }

        var.update $reject_msg {
          value = "The description can be at most 300 characters and cannot contain HTML tags. (E-REQ-009)"
        }
      }
    }

    db.query requirement {
      where = $db.requirement.account_id == $actor.account_id && $db.requirement.name_key == $new_key && $db.requirement.id != $input.requirement_id
      return = {type: "count"}
    } as $clash

    conditional {
      if ($reject_code == "" && $clash > 0) {
        var.update $reject_code {
          value = "E-REQ-003"
        }

        var.update $reject_msg {
          value = "A requirement with that name already exists. (E-REQ-003)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "requirement.rename"
            outcome       : "rejected"
            severity      : "info"
            error_code    : $reject_code
            message       : $reject_msg
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "requirement"
            entity_id     : $input.requirement_id
            correlation_id: $input.correlation_id
          }
        } as $_logged_reject
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $was {
      value = $guard.requirement.name
    }

    var $write_ok {
      value = false
    }

    try_catch {
      try {
        group {
          stack {
            db.patch requirement {
              field_name = "id"
              field_value = $input.requirement_id
              data = {name: $new_name, name_key: $new_key, description: $new_desc, updated_at: "now"}
            } as $updated

            var.update $write_ok {
              value = true
            }
          }
        }
      }

      catch {
        var.update $write_ok {
          value = false
        }
      }
    }

    var $race_msg {
      value = "A requirement with that name already exists. (E-REQ-003)"
    }

    precondition ($write_ok == true) {
      error_type = "inputerror"
      error = $race_msg
    }

    function.run "ops/log_event" {
      input = {
        feature       : "REQ-1"
        step          : "requirement.renamed"
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "A requirement was renamed or its description changed."
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "requirement"
        entity_id     : $input.requirement_id
        correlation_id: $input.correlation_id
        metadata      : {was: $was, now: $new_name}
      }
    } as $_logged
  }

  response = {requirement: $updated}
}
