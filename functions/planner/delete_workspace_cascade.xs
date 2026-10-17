// PLN-3 (US-PLN-3-04) — Delete a plan and everything under it.
//
// ⚠️ NOT PUSHED TO XANO. This file is written and reviewed but the push
// was deliberately held: CLAUDE.md requires the founder to approve any
// delete, and this is the planner's first destructive path. The
// endpoint that calls it (DELETE planner/workspace/{workspace_id}) is
// likewise not created. See the PLN-3 Test Results for what still needs
// verifying once it is approved.
//
// ⚠️ IT LOOPS, AND IT HAS TO — REVISED 2026-10-14.
// The first draft of this file deleted each child table with a single
// `db.del` by `workspace_id`, on the assumption that it removes every
// matching row. **That assumption is now known to be wrong.** PLN-5's
// bulk-visibility endpoint was written the same way with `db.patch` and
// flipped exactly ONE of six agents while reporting success. `db.patch`
// and `db.del` share that field_name/field_value form, so the original
// cascade would have deleted one task, one timeline, one agent and then
// the plan — leaving every other child orphaned, pointing at a plan
// that no longer exists. Precisely the corruption GOV-1's integrity
// audit exists to catch, caused by the cleanup meant to prevent it.
//
// So each child is read and deleted by its own id. Still worth
// re-confirming against the throwaway fixture before trusting it, since
// `db.del`'s multi-row behaviour has not been observed directly — only
// inferred from `db.patch`.
//
// Children first, parent last — tasks, then timelines, then agents,
// then the plan — so nothing is ever left pointing at a row that is
// already gone, even for an instant.
//
// The whole thing is one `db.transaction`: a plan is never
// half-deleted.
//
// This function does NOT decide whether deleting is allowed. The caller
// checks tenancy (planner/assert_workspace) and history
// (planner/workspace_has_history) first. Keeping the decision out of
// here means the cascade can be reused by the account-closing path
// later without re-litigating permissions.
function "planner/delete_workspace_cascade" {
  input {
    int workspace_id filters=min:1
  }

  stack {
    db.query planner_task {
      where = $db.planner_task.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $tasks

    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $timelines

    db.query planner_agent {
      where = $db.planner_agent.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $agents

    db.transaction {
      stack {
        foreach ($tasks) {
          each as $t {
            db.del planner_task {
              field_name = "id"
              field_value = $t.id
            }
          }
        }

        foreach ($timelines) {
          each as $tl {
            db.del planner_timeline {
              field_name = "id"
              field_value = $tl.id
            }
          }
        }

        foreach ($agents) {
          each as $a {
            db.del planner_agent {
              field_name = "id"
              field_value = $a.id
            }
          }
        }

        db.del planner_workspace {
          field_name = "id"
          field_value = $input.workspace_id
        }
      }
    }
  }

  response = {
    deleted: {
      tasks    : ($tasks|count)
      timelines: ($timelines|count)
      agents   : ($agents|count)
      workspace: 1
    }
  }
}
