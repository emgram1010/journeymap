// Query journey_map records owned by the authenticated user.
// Architecture-scoped listing is handled by GET /journey_architecture/{id}/bundle.
query journey_map verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    db.query journey_map {
      where = $db.journey_map.owner_user == $auth.id
      return = {type: "list"}
    } as $model
  }

  response = $model
}