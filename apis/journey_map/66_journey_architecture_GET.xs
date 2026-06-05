// List all Journey Architecture records owned by the authenticated user.
// Sorted by updated_at descending (most recently touched first).
query journey_architecture verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    db.query journey_architecture {
      where = $db.journey_architecture.owner_user == $auth.id
      sort = {updated_at: "desc"}
      return = {type: "list"}
    } as $model
  }

  response = $model
}