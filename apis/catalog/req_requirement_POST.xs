// REQ-1 story 01 — Add a requirement to the account's list. Admin only (an account admin or owner). The name is tidied and checked by req/normalize_name and req/validate_name (empty E-REQ-001, over 60 characters E-REQ-008, HTML E-REQ-002; a bad description E-REQ-009). The same name in another case or spacing is the SAME requirement: the answer is outcome "exists" with the existing one (E-REQ-003 is the meaning), and nothing is created. A NEAR match ("Forklift" vs "Forklift licence") answers outcome "similar" with the matches and creates NOTHING until the caller asks again with confirm_similar = true: the screen shows them first, and an AI caller cannot create a near-duplicate in passing (the TAG-1 pattern). 200 requirements per account (E-REQ-005). Two parallel adds of the same name: the unique index on (account, name_key) refuses the second, and the loser reads the winner's row (outcome "exists"). Events: requirement.created. Every input is passed to function.run explicitly.
query "requirement" verb=POST {
  api_group = "catalog"
  auth = "user"

  input {
    text name? filters=trim
    text description? filters=trim
    bool confirm_similar?
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "requirement/create", entity_id: 0, correlation_id: $input.correlation_id}
    } as $_admin

    function.run "req/validate_name" {
      input = {name: $input.name}
    } as $v

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
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

    var $desc_ok {
      value = (($input.description|strlen) <= 300) && (("/<[a-zA-Z][^>]*>/"|regex_matches:$input.description) == false)
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
      where = $db.requirement.account_id == $actor.account_id
      return = {type: "count"}
    } as $account_count

    db.query requirement {
      where = $db.requirement.account_id == $actor.account_id && $db.requirement.name_key == $v.key
      return = {type: "single"}
    } as $existing

    var $existing_id {
      value = $existing|get:"id":0
    }

    conditional {
      if ($reject_code == "" && $existing_id == 0 && $account_count >= 200) {
        var.update $reject_code {
          value = "E-REQ-005"
        }

        var.update $reject_msg {
          value = "This account already has 200 requirements, which is the limit. Archive or delete one you no longer use. (E-REQ-005)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "requirement.create"
            outcome       : "rejected"
            severity      : "info"
            error_code    : $reject_code
            message       : $reject_msg
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "requirement"
            entity_id     : 0
            correlation_id: $input.correlation_id
          }
        } as $_logged_reject
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    function.run "req/similar" {
      input = {account_id: $actor.account_id, key: $v.key, exclude_id: 0}
    } as $near

    var $near_n {
      value = $near.matches|count
    }

    var $outcome {
      value = "created"
    }

    var $row {
      value = $existing
    }

    conditional {
      if ($existing_id != 0) {
        var.update $outcome {
          value = "exists"
        }
      }

      elseif ($near_n > 0 && $input.confirm_similar != true) {
        var.update $outcome {
          value = "similar"
        }
      }
    }

    var $write_ok {
      value = false
    }

    conditional {
      if ($outcome == "created") {
        try_catch {
          try {
            group {
              stack {
                db.add requirement {
                  data = {
                    account_id : $actor.account_id
                    name       : $v.name
                    name_key   : $v.key
                    description: $input.description
                    is_active  : true
                    created_by : $actor.user_id
                    updated_at : "now"
                  }
                } as $new_row

                var.update $row {
                  value = $new_row
                }

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
      }
    }

    // The loser of a parallel add: the unique index refused it. Read the winner.
    conditional {
      if ($outcome == "created" && $write_ok == false) {
        db.query requirement {
          where = $db.requirement.account_id == $actor.account_id && $db.requirement.name_key == $v.key
          return = {type: "single"}
        } as $winner

        var.update $row {
          value = $winner
        }

        var.update $outcome {
          value = "exists"
        }
      }
    }

    conditional {
      if ($outcome == "created") {
        function.run "ops/log_event" {
          input = {
            feature       : "REQ-1"
            step          : "requirement.created"
            outcome       : "success"
            severity      : "info"
            error_code    : ""
            message       : "A requirement was added to the list."
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "requirement"
            entity_id     : $row.id
            correlation_id: $input.correlation_id
            metadata      : {name: $v.name}
          }
        } as $_logged
      }
    }

    var $shown {
      value = (($outcome == "similar") ? null : $row)
    }
  }

  response = {outcome: $outcome, requirement: $shown, matches: $near.matches}
}
