// PLN-4 (US-PLN-4-03) — The account's model price list.
//
// Readable by any member: everyone sees the cost figures these prices
// produce, so hiding the prices themselves would only make those
// figures unexplainable. Only changing them is admin-only.
//
// Does NOT lazily seed. `GET planner/settings` is the one place that
// creates anything, so there is exactly one seeding path to reason
// about. An account that has never opened the planner gets an empty
// list here, which is the honest answer.
query "model" verb=GET {
  api_group = "planner"
  auth = "user"

  input {
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.query planner_model {
      where = $db.planner_model.account_id == $actor.account_id
      sort = {planner_model.id: "asc"}
      return = {type: "list"}
    } as $models
  }

  response = {models: $models}
}
