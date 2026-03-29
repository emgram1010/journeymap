// Query all journey_map records
query journey_map verb=GET {
  api_group = "journey-map"

  input {
  }

  stack {
    db.query journey_map {
      return = {type: "list"}
    } as $model
  }

  response = $model
}