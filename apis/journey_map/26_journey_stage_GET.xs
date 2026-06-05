// Query all journey_stage records
query journey_stage verb=GET {
  api_group = "journey-map"

  input {
  }

  stack {
    db.query journey_stage {
      return = {type: "list"}
    } as $model
  }

  response = $model
}