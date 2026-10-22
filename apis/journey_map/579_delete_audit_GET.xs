// US-DEL-1-06 (2026-10-18) — Read back what has been deleted.
//
// WHY A NEW READER. The deletes have been recording to `event_log`
// since this morning — who, what, when, and the exact cascade counts.
// But the only endpoint that reads it back (`ops/timeline`, api 4)
// calls `ops/require_platform_admin`, and the founder's own login is
// `is_platform_admin: false`. So the audit existed and the one person
// who needs it could not see it. A log nobody can read is not an
// audit trail, it is just rows.
//
// ACCOUNT-SCOPED, NOT PLATFORM-SCOPED. This answers "what was deleted
// on MY account", which is a different and much safer question than
// the cross-account view ops/timeline exists for. An account admin
// sees their own account's deletes; nobody sees another account's.
//
// PATH DELIBERATELY NOT `journey_map/delete_audit`. A static
// segment after `journey_map/` would be shadowed by
// `journey_map/{journey_map_id}` and 400 on every call — the
// collision that left endpoint 210 dead code for weeks (CLAUDE.md).
// A top-level prefix cannot collide.
//
// READ-ONLY. Returns both successful deletes and refusals: "we
// stopped someone deleting the map a plan was using" is as much a
// part of the record as the deletes that went through.
query delete_audit verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int limit? filters=min:1
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
    } as $actor

    var $account_id {
      value = ($actor.account_id ?? 0)
    }

    precondition ($account_id != 0) {
      error_type = "notfound"
      error = "This login is not attached to an account yet."
    }

    var $cap {
      value = 100
    }

    conditional {
      if ($input.limit != 0) {
        var.update $cap {
          value = $input.limit
        }
      }
    }

    // DEL-1 is the delete feature; every soft, hard and bulk delete
    // path logs under it, so one filter covers them all.
    db.query event_log {
      where = $db.event_log.account_id == $account_id && $db.event_log.feature == "DEL-1"
      sort = {event_log.created_at: "desc"}
      return = {type: "list"}
    } as $rows

    // Who did it, resolved in one query for the whole page rather
    // than one lookup per row.
    var $user_ids {
      value = []
    }

    foreach ($rows) {
      each as $r0 {
        array.push $user_ids {
          value = $r0.user_id
        }
      }
    }

    db.query user {
      where = $db.user.id in $user_ids
      return = {type: "list"}
    } as $users

    var $names {
      value = {}
    }

    var $k {
      value = ""
    }

    foreach ($users) {
      each as $u {
        var.update $k {
          value = $u.id|to_text
        }

        var.update $names {
          value = $names|set:$k:$u.name
        }
      }
    }

    var $events {
      value = []
    }

    var $kept {
      value = 0
    }

    var $who {
      value = null
    }

    var $deleted_count {
      value = 0
    }

    var $refused_count {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        var.update $k {
          value = $r.user_id|to_text
        }

        var.update $who {
          value = $names|get:$k:null
        }

        conditional {
          if ($kept < $cap) {
            array.push $events {
              value = {
                id         : $r.id
                at         : $r.created_at
                step       : $r.step
                outcome    : $r.outcome
                entity_type: $r.entity_type
                entity_id  : $r.entity_id
                by         : $who
                message    : $r.message
                error_code : $r.error_code
                detail     : $r.metadata
              }
            }

            var.update $kept {
              value = $kept + 1
            }
          }
        }
      }
    }

    // Tallies read the LOOP ITEM, never a var set in the same
    // iteration, so the branch writes survive (CLAUDE.md).
    foreach ($rows) {
      each as $r2 {
        conditional {
          if ($r2.outcome == "success") {
            var.update $deleted_count {
              value = $deleted_count + 1
            }
          }
        }

        conditional {
          if ($r2.outcome == "rejected") {
            var.update $refused_count {
              value = $refused_count + 1
            }
          }
        }
      }
    }
  }

  response = {
    account_id    : $account_id
    total         : ($rows|count)
    deleted_count : $deleted_count
    refused_count : $refused_count
    returned      : ($events|count)
    events        : $events
  }
}
