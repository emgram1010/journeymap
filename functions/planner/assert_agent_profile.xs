// PLAN-2 — Agent profile tenancy guard (single id).
//
// Two tenancy paths, because a profile's account isn't a single
// column: a PERSON profile's account comes from `user.account_id`
// (the profile itself never stores one); an AI profile (user_id = 0)
// has no user row, so its own `account_id` column is what's checked
// instead. Same "not found, not denied" answer either way, so an id
// in another account can't be probed.
function "planner/assert_agent_profile" {
  input {
    int account_id filters=min:1
    int profile_id filters=min:1
  }

  stack {
    db.get agent_profile {
      field_name = "id"
      field_value = $input.profile_id
    } as $profile

    var $resolved_account {
      value = 0
    }

    conditional {
      if ($profile != null && $profile.user_id == 0) {
        var.update $resolved_account {
          value = $profile.account_id
        }
      }
    }

    conditional {
      if ($profile != null && $profile.user_id != 0) {
        db.get user {
          field_name = "id"
          field_value = $profile.user_id
        } as $owner

        conditional {
          if ($owner != null) {
            var.update $resolved_account {
              value = $owner.account_id
            }
          }
        }
      }
    }

    var $belongs {
      value = ($profile != null && $resolved_account == $input.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Agent profile not found"
    }
  }

  response = {profile: $profile}
}
