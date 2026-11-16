// COP-1 story 04 - Health page "AI tool calls" panel. See functions/ops/tool_calls_panel.xs.
// Platform-admin only, like every ops/* endpoint (E-OBS-001).
query "ops/tool_calls" verb=GET {
  api_group = "Ops"
  auth = "user"

  input {
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    function.run "ops/tool_calls_panel" {
      input = {}
    } as $panel
  }

  response = $panel
}
