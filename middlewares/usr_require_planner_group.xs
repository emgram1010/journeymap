// USR-2 (US-USR-2-04) — the gate for the planner API group, which the Planner and the performer app share. Holds no rule of its own: usr/planner_group_module says which module this request needs (execution, planning, or either), and usr/assert_module_access decides. An unclassified endpoint needs the Planner grant. exception_policy MUST be "critical". Never attach to the Authentication group.
//
// (Everything below this first line is local-only commentary. The leading
// comment IS the live description, so the live one is the single line above.)
//
// WHY ONE GROUP-LEVEL GATE, NOT `planner/resolve_actor`. The first plan was
// to add the check to that guard, since all 64 planner endpoints call it. A
// review before building found 17 journey-map endpoints call it too — a
// Planner default there would have refused every Intelligent-Layer-only
// person on their own maps. A group-level middleware touches only this group,
// and covers endpoints that do not exist yet.
//
// HOW IT TELLS PLANNER FROM EXECUTION. A middleware CAN read the request:
// `$env.$request_uri` and `$env.$request_method` (proven 2026-11-14; the epic
// had this down as "probably impossible"). The classification is its own
// function so it is testable without a token.
//
// PROVEN 2026-11-14 on a scratch group, 16 of 16, real tokens over real HTTP:
// planner-only, execution-only, intelligence-only and switched-off users
// against planner-only, execution-only and shared endpoints
// (`product/stories/Epic-13/tests/usr2_planner_matrix.py`).
//
// `$auth.id ?? 0`, never `$auth|get:"id":0` — the latter is rewritten on save
// to `$auth[""]|get...` and fails every request with a 500.
middleware usr_require_planner_group {
  input {
    json vars
    enum type {
      values = ["pre", "post"]
    }
  }

  stack {
    var $caller_id {
      value = $auth.id ?? 0
    }

    conditional {
      if ($caller_id != 0) {
        function.run "usr/planner_group_module" {
          input = {uri: $env.$request_uri, method: $env.$request_method}
        } as $need

        function.run "usr/assert_module_access" {
          input = {
            actor_user_id: $caller_id
            module       : $need.module
            or_module    : $need.or_module
            step         : "middleware/planner_group"
          }
        } as $_allowed
      }
    }
  }

  response = null
  response_strategy = "merge"
  exception_policy = "critical"
}
