// PLN-5 (US-PLN-5-04) — Move a timeline's tasks back to the backlog.
//
// THE SHARED PRIMITIVE for "this timeline is going away, but the work
// isn't". Reused by PLN-5 (delete an agent), PLN-6 (delete a timeline)
// and PLN-7 (unschedule a task). Nothing here deletes anything — it is
// purely a move, which is why it exists separately from the cascades
// that call it, and why it could be built and verified while the
// delete paths wait for approval.
//
// ORDER IS PRESERVED, TWICE OVER:
//   - tasks already in the backlog keep their seq untouched;
//   - the returning tasks are appended after them, in their existing
//     timeline order, so a sensible running order survives the move.
// Without this they would all land on seq 0 and the backlog would
// silently reshuffle itself.
//
// "Backlog" is `timeline_id = 0`, not null — there are no real nullable
// foreign keys in this workspace (docs/planner-data-model.md).
//
// Each task is patched by its own id in a loop: `db.patch` with a
// non-unique field_name only ever updates the FIRST match (CLAUDE.md).
function "planner/return_tasks_to_backlog" {
  input {
    int workspace_id filters=min:1
    int timeline_id filters=min:1
  }

  stack {
    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id && $db.planner_task.timeline_id == 0
      return = {type: "list"}
    } as $backlog

    // Starts at 0, NOT -1. seq is a 1..n scheme, so "nothing in the
    // backlog yet" must make the first returned task seq 1 — starting
    // at -1 handed it seq 0 and left the container failing PLN-8's
    // SEQ_GAP_OR_DUP check. Latent until 2026-10-16: the only caller
    // that could hit an empty backlog was the agent/timeline delete
    // cascade, which was unpushed until then, and the other caller
    // (planner/place_task) resequences afterwards so it never showed.
    // Found by the integrity audit on the cascades' very first run.
    var $max_seq {
      value = 0
    }

    foreach ($backlog) {
      each as $b {
        conditional {
          if ($b.seq > $max_seq) {
            var.update $max_seq {
              value = $b.seq
            }
          }
        }
      }
    }

    db.query planner_task {
      where = $db.planner_task.timeline_id == $input.timeline_id
      sort = {planner_task.seq: "asc", planner_task.id: "asc"}
      return = {type: "list"}
    } as $moving

    var $next_seq {
      value = $max_seq
    }

    var $moved_ids {
      value = []
    }

    db.transaction {
      stack {
        foreach ($moving) {
          each as $t {
            var.update $next_seq {
              value = $next_seq + 1
            }

            db.patch planner_task {
              field_name = "id"
              field_value = $t.id
              data = {timeline_id: 0, seq: $next_seq, updated_at: "now"}
            } as $patched

            array.push $moved_ids {
              value = $t.id
            }
          }
        }
      }
    }
  }

  response = {
    tasks_returned: ($moving|count)
    moved_ids     : $moved_ids
    first_seq     : ($max_seq + 1)
    last_seq      : $next_seq
  }
}
