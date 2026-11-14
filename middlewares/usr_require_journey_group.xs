// USR-2 (US-USR-2-03) — the gate for the journey-map API group (the Intelligent Layer). Holds no rule of its own: usr/journey_group_module says what this request needs (the Intelligent Layer for almost everything; no module for account/me; either grant for the old map-picker door), usr/assert_module_access decides, and usr/assert_user_active covers the no-module case. An unclassified endpoint needs the Intelligent Layer. exception_policy MUST be "critical". Never attach to the Authentication group.
//
// (Everything below this first line is local-only commentary.)
//
// WHY NOT THE SIMPLER `usr_require_module_intelligence`. That one checks one
// module for every request. Reviewing the group before attaching showed
// `account/me` — the Account Settings page, open to every signed-in person —
// lives in this same group, so the simple lock would have broken that page
// for anyone without the Intelligent Layer. The simple middleware still
// exists and is attached to nothing real.
//
// PROVEN 2026-11-14: 15 of 15 on a scratch group, then on the real group
// (`product/stories/Epic-13/tests/usr2_journey_matrix.py`).
middleware usr_require_journey_group {
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
        function.run "usr/journey_group_module" {
          input = {uri: $env.$request_uri, method: $env.$request_method}
        } as $need

        conditional {
          if ($need.none) {
            function.run "usr/assert_user_active" {
              input = {
                user_id   : $caller_id
                account_id: 0
                feature   : "USR-2"
                step      : "middleware/journey_group"
              }
            } as $_active
          }

          else {
            function.run "usr/assert_module_access" {
              input = {
                actor_user_id: $caller_id
                module       : $need.module
                or_module    : $need.or_module
                step         : "middleware/journey_group"
              }
            } as $_allowed
          }
        }
      }
    }
  }

  response = null
  response_strategy = "merge"
  exception_policy = "critical"
}
