// Delete journey_lens record
query "journey_lens/{journey_lens_id}" verb=DELETE {
  api_group = "journey-map"

  input {
    int journey_lens_id? filters=min:1
  }

  stack {
    db.del journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    }
  }

  response = null
}