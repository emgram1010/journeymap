// PLAN-2/PLAN-3 — May these agent profiles be attached to a template?
//
// Same shape as `planner/assert_maps_publishable`: two passes (CLAUDE.md
// rule — pass 1 records each lookup as a field, pass 2 branches on the
// loop item), returns the FIRST offending profile so the caller can
// name it rather than an id.
//
// Two tenancy paths per profile (see `assert_agent_profile`'s own
// header): a person profile's account comes from `user.account_id`; an
// AI profile (user_id = 0) carries its own `account_id` column. Both
// are resolved here in one pass before the ok/not-found/not-eligible
// checks run.
function "planner/assert_agent_profiles_eligible" {
  input {
    int account_id filters=min:1
    json profile_ids
  }

  stack {
    var $requested {
      value = $input.profile_ids
    }

    var $ok {
      value = true
    }

    var $bad_reason {
      value = ""
    }

    var $bad_profile_id {
      value = 0
    }

    conditional {
      if (($requested|count) > 0) {
        db.query agent_profile {
          where = $db.agent_profile.id in $requested
          return = {type: "list"}
        } as $profiles

        var $user_ids {
          value = []
        }

        foreach ($profiles) {
          each as $p {
            conditional {
              if ($p.user_id != 0) {
                array.push $user_ids {
                  value = $p.user_id
                }
              }
            }
          }
        }

        var $owner_accounts {
          value = {}
        }

        conditional {
          if (($user_ids|count) > 0) {
            db.query user {
              where = $db.user.id in $user_ids
              return = {type: "list"}
            } as $owners

            var $okey {
              value = ""
            }

            foreach ($owners) {
              each as $u {
                var.update $okey {
                  value = $u.id|to_text
                }

                var.update $owner_accounts {
                  value = $owner_accounts|set:$okey:$u.account_id
                }
              }
            }
          }
        }

        // Resolve each profile's account once, into a lookup keyed by
        // profile id — same seeded-map pattern 553_template_GET.xs uses.
        var $found {
          value = {}
        }

        var $fkey {
          value = ""
        }

        var $resolved_account {
          value = 0
        }

        var $uid_key {
          value = ""
        }

        foreach ($profiles) {
          each as $p {
            var.update $fkey {
              value = $p.id|to_text
            }

            var.update $resolved_account {
              value = $p.account_id
            }

            var.update $uid_key {
              value = $p.user_id|to_text
            }

            conditional {
              if ($p.user_id != 0) {
                var.update $resolved_account {
                  value = ($owner_accounts|get:$uid_key:0)
                }
              }
            }

            var.update $found {
              value = $found|set:$fkey:{account_id: $resolved_account, is_eligible: $p.is_eligible, name: $p.name}
            }
          }
        }

        var $checks {
          value = []
        }

        var $ckey {
          value = ""
        }

        foreach ($requested) {
          each as $pid {
            var.update $ckey {
              value = $pid|to_text
            }

            array.push $checks {
              value = {profile_id: $pid, info: ($found|get:$ckey:null)}
            }
          }
        }

        foreach ($checks) {
          each as $c {
            conditional {
              if ($c.info == null && $ok == true) {
                var.update $ok {
                  value = false
                }

                var.update $bad_reason {
                  value = "not_found"
                }

                var.update $bad_profile_id {
                  value = $c.profile_id
                }
              }
            }

            conditional {
              if ($c.info != null && $c.info.account_id != $input.account_id && $ok == true) {
                var.update $ok {
                  value = false
                }

                var.update $bad_reason {
                  value = "not_found"
                }

                var.update $bad_profile_id {
                  value = $c.profile_id
                }
              }
            }

            conditional {
              if ($c.info != null && $c.info.account_id == $input.account_id && $c.info.is_eligible == false && $ok == true) {
                var.update $ok {
                  value = false
                }

                var.update $bad_reason {
                  value = "not_eligible"
                }

                var.update $bad_profile_id {
                  value = $c.profile_id
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    ok           : $ok
    reason       : $bad_reason
    profile_id   : $bad_profile_id
    checked_count: ($requested|count)
  }
}
