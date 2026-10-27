// EST-1 (US-EST-1-07) — Health page Estimates panel. See
// functions/ops/estimates_panel.xs.
query "ops/estimates" verb=GET {
  api_group = "Ops"
  auth = "user"

  input {
    text since? filters=trim
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    function.run "ops/estimates_panel" {
      input = {since: $input.since}
    } as $panel
  }

  response = $panel
}
