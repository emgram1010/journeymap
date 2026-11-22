// DEMAND-1 — every change an admin makes to incoming orders, through one door (orders/admin holds every rule and refuses anyone who is not a person and an account admin): route_save, key_create (the new key is returned once, here), route_delete, flag_clear, retry.
query "order-setup-change" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    text action filters=trim
    int route_id?
    text source_system? filters=trim
    text match_fulfilment? filters=trim
    int workspace_id?
    int journey_map_id?
    bool disabled?
    int work_item_id?
    int order_inbox_id?
  }

  stack {
    var $enabled {
      value = $input.disabled != true
    }

    function.run "orders/admin" {
      input = {actor_user_id: $auth.id, action: $input.action, route_id: $input.route_id, source_system: $input.source_system, match_fulfilment: $input.match_fulfilment, workspace_id: $input.workspace_id, journey_map_id: $input.journey_map_id, is_enabled: $enabled, work_item_id: $input.work_item_id, order_inbox_id: $input.order_inbox_id}
    } as $r
  }

  response = $r
}
