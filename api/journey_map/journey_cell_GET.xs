// Query all journey_cell records
query journey_cell verb=GET {
  api_group = "journey-map"

  input {
  }

  stack {
    db.query journey_cell {
      return = {type: "list"}
    } as $model
  }

  response = $model
  guid = "PNTBG12i78LjHCu-v4_Y7DjRfoI"
}