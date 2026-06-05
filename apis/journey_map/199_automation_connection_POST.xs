// Register an external automation tool connection against a Journey Architecture.
// Emgram will POST the compiled snapshot to webhook_url on every publish.
// owner_user inherited from journey_architecture — never accepted from client.
query automation_connection verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
    enum provider? {
      values = ["n8n", "make", "zapier", "custom"]
    }
  
    text label? filters=trim
    text webhook_url? filters=trim
  }

  stack {
    precondition ($input.journey_architecture_id != null) {
      error_type = "inputerror"
      error = "journey_architecture_id is required"
    }
  
    precondition ($input.webhook_url != null) {
      error_type = "inputerror"
      error = "webhook_url is required"
    }
  
    precondition ($input.provider != null) {
      error_type = "inputerror"
      error = "provider is required"
    }
  
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $arch
  
    precondition ($arch != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    precondition ($arch.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    db.add automation_connection {
      enforce_hidden_fields = false
      data = {
        created_at          : "now"
        updated_at          : "now"
        journey_architecture: $input.journey_architecture_id
        provider            : $input.provider
        label               : $input.label
        webhook_url         : $input.webhook_url
        status              : "active"
        owner_user          : $auth.id
      }
    } as $connection
  }

  response = $connection
}