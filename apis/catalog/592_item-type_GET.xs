// CAT-1 (US-CAT-1-03) — List the caller's account's item types.
// Active-only by default; ?include_inactive=1 (or true) includes
// deactivated ones too, same default shape PLAN-1's template list and
// PLAN-2's agent-profile list already use for "what can I use right now".
query "item-type" verb=GET {
  api_group = "catalog"
  auth = "user"

  input {
    bool include_inactive?
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.query item_type {
      where = $db.item_type.account_id == $actor.account_id && ($input.include_inactive == true || $db.item_type.is_active == true)
      sort = {item_type.label: "asc"}
      return = {type: "list"}
    } as $items
  }

  response = {items: $items}
}
