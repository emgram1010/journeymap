// PLN-8 (US-PLN-8-02) — Run the integrity audit for this account.
// Admin only.
//
// Read-only, and it reports rather than repairs. Admin-only not
// because the result is secret — it is this account's own data — but
// because a list of internal ids and invariant codes is an
// engineer-facing artefact, and putting it in front of every member
// invites someone to "fix" it by hand.
//
// A clean account returns `clean: true` and an empty list, which is
// the answer the Health page wants most days.
query "workspace/integrity" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_admin" {
      input = {role: $actor.role}
    }

    function.run "planner/integrity_audit" {
      input = {account_id: $actor.account_id}
    } as $audit

    // Only worth an event when something is actually wrong — a nightly
    // clean run must not fill the log with noise.
    conditional {
      if ($audit.clean == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "PLN-8"
            step       : "integrity_audit"
            outcome    : "failure"
            severity   : "warn"
            user_id    : $actor.user_id
            account_id : $actor.account_id
            entity_type: "planner_workspace"
            error_code : "E-GOV-006"
            message    : "Planner integrity audit found violations."
            metadata   : {violation_count: $audit.violation_count}
          }
        }
      }
    }
  }

  response = $audit
}
