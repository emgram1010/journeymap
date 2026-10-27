// CAT-1 (US-CAT-1-03) — List the caller's account's methods. Same
// shape as item-type's own list endpoint.
query "method" verb=GET {
  api_group = "catalog"
  auth = "user"

  input {
    bool include_inactive?
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.query method {
      where = $db.method.account_id == $actor.account_id && ($input.include_inactive == true || $db.method.is_active == true)
      sort = {method.label: "asc"}
      return = {type: "list"}
    } as $methods
  }

  response = {methods: $methods}
}
