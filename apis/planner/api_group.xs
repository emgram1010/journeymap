// Planner backend (phase-3 PLN-1 to PLN-8). Every endpoint declares auth = "user" and calls the planner/* guard functions for tenancy and role checks.
//
// PLN-2 (US-PLN-2-05) — The planner's API group. Every endpoint added here
// declares `auth = "user"` and opens with planner/resolve_actor, then the
// guard for whatever it is about to touch. No endpoint re-implements a
// tenancy or role check inline — that drift is the whole reason PLN-2 exists.
// Created in workspace 1 ("emgram1010") on 2026-10-14, apigroup_id 24.
//
// USR-2 (2026-11-14): `usr_require_planner_group` is attached here. It runs
// before every endpoint in the group and refuses anyone who is switched off
// or lacks the module that request needs (Planner, Execution, or either —
// see functions/usr/planner_group_module.xs). Detaching it is the rollback:
// push this file without the `middleware` line.
//
// `swagger = {active: true}` is written out on purpose. Pushing this group
// WITHOUT that line silently turned the API docs off (found 2026-11-14).
api_group planner {
  canonical = "PE5iDldw"
  swagger = {active: true}
  tags = ["phase-3", "planner"]
  middleware = {pre: [{name: "usr_require_planner_group"}]}
}
