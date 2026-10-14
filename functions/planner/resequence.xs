// PLN-7 (US-PLN-7-01) — Make a container's seq exactly 1..n.
//
// THE ONE PLACE seq IS EVER NORMALISED. Every mutation (create, place,
// reorder, delete) ends by calling this for each container it touched,
// source and destination. Nothing else is allowed to invent a seq, so
// there is exactly one definition of "gapless" to get right.
//
// A "container" is a timeline, or the workspace's backlog. The backlog
// is `timeline_id = 0` — there are no real nullable foreign keys here
// (docs/planner-data-model.md) — so `timeline_id` deliberately has no
// `min:1` filter: 0 is a legitimate value meaning "the backlog".
//
// Ordering is by current seq, then id. The id tiebreak matters: two
// tasks can briefly share a seq mid-move, and without it the result
// would depend on whatever order the database felt like returning.
//
// IDEMPOTENT by construction — running it on an already-correct
// container rewrites the same values (US-PLN-7-01 requires this, and
// callers do double-call it when source and destination are the same).
// Confirmed live: two consecutive runs returned identical orders.
//
// Each row is patched by its own id: `db.patch` with a non-unique
// field only ever touches the first match (CLAUDE.md).
function "planner/resequence" {
  input {
    int workspace_id filters=min:1
    int timeline_id
  }

  stack {
    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id && $db.planner_task.timeline_id == $input.timeline_id
      sort = {planner_task.seq: "asc", planner_task.id: "asc"}
      return = {type: "list"}
    } as $tasks

    var $n {
      value = 0
    }

    var $order {
      value = []
    }

    db.transaction {
      stack {
        foreach ($tasks) {
          each as $t {
            var.update $n {
              value = $n + 1
            }

            db.patch planner_task {
              field_name = "id"
              field_value = $t.id
              data = {seq: $n, updated_at: "now"}
            } as $patched

            array.push $order {
              value = {id: $t.id, seq: $n}
            }
          }
        }
      }
    }
  }

  response = {
    container_timeline_id: $input.timeline_id
    count                : $n
    order                : $order
  }
}
