// List Journey Links for the authenticated user.
// Optionally filter by source_map or target_map — both are ignore-if-null.
query journey_link verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int source_map?
    int target_map?
  }

  stack {
    db.query journey_link {
      where = $db.journey_link.owner_user == $auth.id && $db.journey_link.source_map ==? $input.source_map && $db.journey_link.target_map ==? $input.target_map
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $links
  }

  response = $links
}