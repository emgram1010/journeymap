// Get journey_lens record
query "journey_lens/{journey_lens_id}" verb=GET {
  api_group = "journey-map"

  input {
    int journey_lens_id? filters=min:1
  }

  stack {
    db.get journey_lens {
      field_name = "id"
      field_value = $input.journey_lens_id
    } as $model
  
    precondition ($model != null) {
      error_type = "notfound"
      error = "Not Found"
    }
  }

  response = $model
}