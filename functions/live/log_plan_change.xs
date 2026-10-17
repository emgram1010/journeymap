// LIVE-1 (US-LIVE-1-04) — Record a planner change made AFTER the day
// went live.
//
// Called by the planner's own edit endpoints. It does nothing at all
// when the timeline has not been published — a draft day can be
// rearranged freely and there is nothing to measure the change
// against yet. That "do nothing quietly" behaviour is why callers can
// invoke it unconditionally instead of each one re-deciding whether
// the day is live. Confirmed live: the same edit wrote a row on a
// published day and nothing on a draft one.
//
// WHY IT MATTERS: publishing freezes what the performer sees, not
// what the planner may do. Without this log, a day quietly
// rearranged after publishing would look in hindsight as though it
// had always been planned that way, and every plan-vs-actual figure
// drawn from it would be flattering and wrong.
//
// `item_ref` points at the PUBLISHED item, never at a live row, so a
// change stays attached to something that still exists even after
// the planner task is removed (review finding F5).
//
// It never throws: a logging problem must not break the planner's
// edit, exactly as `ops/log_event` behaves.
function "live/log_plan_change" {
  input {
    int timeline_id filters=min:1
    text item_ref filters=trim
    enum change_type {
      values = ["moved", "added", "removed", "duration_changed", "reassigned"]
    }

    json before?
    json after?
    int changed_by?
  }

  stack {
    var $logged {
      value = false
    }

    var $publication_id {
      value = 0
    }

    try_catch {
      try {
        db.query plan_publication {
          where = $db.plan_publication.timeline_id == $input.timeline_id
          return = {type: "list"}
        } as $pubs

        conditional {
          if (($pubs|count) > 0) {
            var.update $publication_id {
              value = ($pubs|first).id
            }

            db.add plan_change_log {
              data = {
                timeline_id        : $input.timeline_id
                plan_publication_id: $publication_id
                item_ref           : $input.item_ref
                change_type        : $input.change_type
                before             : $input.before
                after              : $input.after
                changed_by         : $input.changed_by
              }
            } as $row

            var.update $logged {
              value = true
            }
          }
        }
      }

      catch {
        // Never break the planner's edit because the audit trail
        // failed. The failure itself is visible through OBS-1.
        debug.log {
          value = "plan_change_log write failed"
        }
      }
    }
  }

  response = {
    logged             : $logged
    plan_publication_id: $publication_id
  }
}
