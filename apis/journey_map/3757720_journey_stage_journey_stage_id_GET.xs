// Get journey_stage record
query "journey_stage/{journey_stage_id}" verb=GET {
  api_group = "journey-map"

  input {
    int journey_stage_id? filters=min:1
  }

  stack {
    db.get journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    } as $model
  
    precondition ($model != null) {
      error_type = "notfound"
      error = "Not Found"
    }
  }

  response = $model
}