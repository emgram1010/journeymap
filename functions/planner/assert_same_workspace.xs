// PLN-2 (US-PLN-2-04) — Cross-reference guard.
//
// Catches the case the tenancy guards cannot: both entities are in the
// caller's own account, so every account check passes, but they live in
// two different plans. Moving a task into another plan's timeline is the
// example that matters (PLN-7).
//
// `inputerror`, not `accessdenied`: nothing was forbidden, the request
// was simply incoherent. The caller may see both rows.
//
// Callers pass the two `workspace_id`s they already hold from the entity
// guards above, so this costs no extra query.
function "planner/assert_same_workspace" {
  input {
    int workspace_id_a filters=min:1
    int workspace_id_b filters=min:1
  }

  stack {
    precondition ($input.workspace_id_a == $input.workspace_id_b) {
      error_type = "inputerror"
      error = "Entities must belong to the same workspace"
    }
  }

  response = {ok: true, workspace_id: $input.workspace_id_a}
}
