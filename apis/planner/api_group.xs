// PLN-2 (US-PLN-2-05) — The planner's API group.
//
// Every endpoint added here (PLN-3 … PLN-8) declares `auth = "user"` and
// opens with planner/resolve_actor, then the guard for whatever it is
// about to touch. No endpoint re-implements a tenancy or role check
// inline — that drift is the whole reason PLN-2 exists.
//
// `api_group "journey-map"` is untouched.
//
// Created in workspace 1 ("emgram1010") on 2026-10-14, apigroup_id 24.
api_group planner {
  canonical = "PE5iDldw"
  tags = ["phase-3", "planner"]
}
