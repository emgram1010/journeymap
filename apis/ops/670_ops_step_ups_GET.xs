// COP-13 story 05 (Health part) - the "Stronger model" panel: step-ups per day per business for the
// last 7 days, and how many were approved, declined, expired or refused by the daily limit.
// See functions/ops/step_ups_panel.xs. Platform-admin only, like every ops/* endpoint (E-OBS-001).
query "ops/step_ups" verb=GET {
  api_group = "Ops"
  auth = "user"

  input {
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    function.run "ops/step_ups_panel" {
      input = {}
    } as $panel
  }

  response = $panel
}
