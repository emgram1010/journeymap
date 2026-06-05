// Delete journey_stage record
query "journey_stage/{journey_stage_id}" verb=DELETE {
  api_group = "journey-map"

  input {
    int journey_stage_id? filters=min:1
  }

  stack {
    db.del journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
    }
  }

  response = null
}