// Edit journey_stage record
query "journey_stage/{journey_stage_id}" verb=PATCH {
  api_group = "journey-map"

  input {
    int journey_stage_id? filters=min:1
    dblink {
      table = "journey_stage"
    }
  }

  stack {
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    db.patch journey_stage {
      field_name = "id"
      field_value = $input.journey_stage_id
      data = `$input|pick:($raw_input|keys)`|filter_null|filter_empty_text
    } as $model
  }

  response = $model
}