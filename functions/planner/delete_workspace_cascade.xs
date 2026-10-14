// PLN-3 (US-PLN-3-04) — Delete a plan and everything under it.
//
// ⚠️ NOT PUSHED TO XANO. This file is written and reviewed but the push
// was deliberately held: CLAUDE.md requires the founder to approve any
// delete, and this is the planner's first destructive path. The
// endpoint that calls it (DELETE planner/workspace/{workspace_id}) is
// likewise not created. See the PLN-3 Test Results for what still needs
// verifying once it is approved.
//
// Children first, parent last — tasks, then timelines, then agents, then
// the plan — so nothing is ever left pointing at a row that is already
// gone, even for an instant.
//
// The whole thing is one `db.transaction`: a plan is never half-deleted.
// Without it, a failure partway through would leave orphaned timelines
// with no plan, which is exactly the kind of mess GOV-1's integrity
// audit exists to catch.
//
// This function does NOT decide whether deleting is allowed. The caller
// checks tenancy (planner/assert_workspace) and history
// (planner/workspace_has_history) first. Keeping the decision out of
// here means the cascade can be reused by the account-closing path
// later without re-litigating permissions.
//
// Counts are taken BEFORE the deletes, because afterwards there is
// nothing left to count.
//
// UNVERIFIED ASSUMPTION, must be tested before this is trusted:
// `db.del` with field_name/field_value is assumed to delete EVERY
// matching row, not just the first. If it only deletes one, each of the
// three child deletes needs to become a loop instead. The CLAUDE.md
// note on `db.del` only documents deleting a single record by field,
// so this genuinely is not known yet.
function "planner/delete_workspace_cascade" {
  input {
    int workspace_id filters=min:1
  }

  stack {
    function.run "planner/workspace_counts" {
      input = {workspace_id: $input.workspace_id}
    } as $before

    db.transaction {
      stack {
        db.del planner_task {
          field_name = "workspace_id"
          field_value = $input.workspace_id
        }

        db.del planner_timeline {
          field_name = "workspace_id"
          field_value = $input.workspace_id
        }

        db.del planner_agent {
          field_name = "workspace_id"
          field_value = $input.workspace_id
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
      tasks    : $before.task_count
      timelines: $before.timeline_count
      agents   : $before.agent_count
      workspace: 1
    }
  }
}
