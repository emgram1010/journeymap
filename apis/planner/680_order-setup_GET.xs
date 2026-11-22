// DEMAND-1 — the incoming-orders screen's data, for an admin who is a person (orders/overview holds every rule). No key or hash is returned.
query "order-setup" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
  }

  stack {
    function.run "orders/overview" {
      input = {actor_user_id: $auth.id}
    } as $o
  }

  response = $o
}
