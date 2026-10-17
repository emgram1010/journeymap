// OBS-1 (US-OBS-1-08, Copy diagnostic bundle button) — Admin-only. Same
// data as ops/timeline, kept as a separate, clearly-named endpoint so the
// Health page's "Copy diagnostic bundle" action has its own stable
// contract, independent of how the drill-down view happens to be wired.
query "ops/bundle" verb=GET {
  api_group = "Ops"
  auth = "user"

  input {
    text correlation_id? filters=trim
    text entity_type? filters=trim
    int entity_id?
    int account_id?
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    function.run "ops/build_diagnostic_bundle" {
      input = {
        correlation_id: $input.correlation_id
        entity_type   : $input.entity_type
        entity_id     : $input.entity_id
        account_id    : $input.account_id
      }
    } as $bundle
  }

  response = $bundle
}
