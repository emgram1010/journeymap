// OBS-1 (US-OBS-1-06, grouping only — acknowledgement is deferred) —
// Groups failure/rejected event_log rows into "issues" on read. Nothing
// is duplicated in storage; this just aggregates existing rows.
//
// fingerprint = feature ~ "::" ~ step ~ "::" ~ (error_code or "none").
// This MUST match the frontend's ops/fingerprint.ts formula exactly
// (same three parts, same separator, same "none" fallback), so that when
// acknowledgement (US-OBS-1-06, deferred) is built later, a fingerprint
// computed in the browser matches one computed here.
//
// REWRITTEN 2026-10-13 after a live push: the original version used
// array.map + array.group_by + object.entries with nested $this[1][0]
// indexing, which this workspace rejected at runtime ("Missing var
// entry: this") as soon as real data flowed through it. Rewritten with
// only primitives confirmed working live here: foreach/each, var,
// var.update, conditional, array.push, |get, |set — the same style as
// the existing tasks/11_prune_event_log.xs.
//
// Also fixes a second live finding: an omitted optional text/int input
// arrives as "" / 0, not null, so `$input.x ?? fallback` never
// triggered. Replaced with explicit emptiness checks everywhere.
function "ops/group_issues" {
  description = "Group failure/rejected events into issues. Read-only; nothing is written."

  input {
    int account_id? {
      description = "Narrow to one account. Omitted = every account (admin-only view)."
    }

    text since? filters=trim {
      description = "ISO timestamp lower bound. Defaults to 30 days ago when omitted."
    }
  }

  stack {
    var $since {
      value = now|transform_timestamp:"30 days ago":"UTC"
    }

    conditional {
      if ($input.since != null && $input.since != "") {
        var.update $since {
          value = $input.since
        }
      }
    }

    var $account_filter_active {
      value = ($input.account_id != null && $input.account_id != 0)
    }

    db.query event_log {
      where = $db.event_log.created_at >= $since && ($db.event_log.outcome == "failure" || $db.event_log.outcome == "rejected") && ($account_filter_active == false || $db.event_log.account_id == $input.account_id)
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $events

    function.run "ops/error_catalog" {
      input = {}
    } as $catalog

    var $issues_by_fingerprint {
      value = {}
    }

    var $fingerprint_order {
      value = []
    }

    foreach ($events) {
      each as $event {
        var $fp {
          value = ($event.feature ?? "") ~ "::" ~ ($event.step ?? "") ~ "::" ~ ($event.error_code ?? "none")
        }

        var $existing {
          value = $issues_by_fingerprint|get:$fp:null
        }

        var $catalog_entry {
          value = $catalog|get:($event.error_code ?? ""):null
        }

        conditional {
          if ($existing == null) {
            var.update $issues_by_fingerprint {
              value = $issues_by_fingerprint|set:$fp:({}|set:"fingerprint":$fp|set:"feature":$event.feature|set:"step":$event.step|set:"error_code":$event.error_code|set:"severity":($event.severity ?? "error")|set:"count":1|set:"first_seen":$event.created_at|set:"last_seen":$event.created_at|set:"latest_message":$event.message|set:"sample_correlation_id":$event.correlation_id|set:"owner":($catalog_entry|get:"owner":"engineer")|set:"user_message":($catalog_entry|get:"user_message":null)|set:"fix_hint":($catalog_entry|get:"fix_hint":null))
            }

            array.push $fingerprint_order {
              value = $fp
            }
          }

          else {
            var.update $issues_by_fingerprint {
              value = $issues_by_fingerprint|set:$fp:($existing|set:"count":($existing.count + 1)|set:"last_seen":$event.created_at|set:"latest_message":$event.message|set:"sample_correlation_id":$event.correlation_id)
            }
          }
        }
      }
    }

    var $issues {
      value = []
    }

    foreach ($fingerprint_order) {
      each as $fp {
        array.push $issues {
          value = $issues_by_fingerprint|get:$fp:null
        }
      }
    }
  }

  response = {issues: $issues, since: $since}
}
