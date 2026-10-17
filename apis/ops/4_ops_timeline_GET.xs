// OBS-1 (US-OBS-1-07, drill-down) — Admin-only. The full ordered timeline
// for one correlation id or one entity (job, plan, map, ...), used by the
// Health page's drill-down view. Thin wrapper over
// ops/build_diagnostic_bundle so the drill-down and the "Copy diagnostic
// bundle" button are always looking at the same events.
query "ops/timeline" verb=GET {
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
