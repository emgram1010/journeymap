// Edit journey_lens record
query "journey_lens/{journey_lens_id}" verb=PATCH {
  api_group = "journey-map"

  input {
    int journey_lens_id? filters=min:1
    dblink {
      table = "journey_lens"
    }
  }

  stack {
    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input
  
    db.patch journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
      data = `$input|pick:($raw_input|keys)`|filter_null|filter_empty_text
    } as $model
  }

  response = $model
}