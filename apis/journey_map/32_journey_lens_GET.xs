// Query all journey_lens records
query journey_lens verb=GET {
  api_group = "journey-map"

  input {
  }

  stack {
    db.query journey_lens {
      return = {type: "list"}
    } as $model
  }

  response = $model
}