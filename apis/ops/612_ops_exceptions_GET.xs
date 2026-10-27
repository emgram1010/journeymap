// EXC-1 (US-EXC-1-07) — Health page Exceptions panel. See
// functions/ops/exceptions_panel.xs. Platform-admin only, like every
// ops/* endpoint (E-OBS-001).
query "ops/exceptions" verb=GET {
  api_group = "Ops"
  auth = "user"

  input {
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    function.run "ops/exceptions_panel" {
      input = {}
    } as $panel
  }

  response = $panel
}
