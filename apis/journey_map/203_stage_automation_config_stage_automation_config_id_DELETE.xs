// Soft-delete a stage_automation_config record by setting status to "disabled".
// Hard deletes are not supported — disabled records are excluded from snapshot compilation
// but preserved for audit trail purposes.
query "stage_automation_config/{stage_automation_config_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int stage_automation_config_id? filters=min:1
  }

  stack {
    db.get stage_automation_config {
      field_name = "id"
      field_value = $input.stage_automation_config_id
    } as $existing
  
    precondition ($existing != null) {
      error_type = "notfound"
      error = "Stage automation config not found"
    }
  
    precondition ($existing.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    db.patch stage_automation_config {
      field_name = "id"
      field_value = $input.stage_automation_config_id
      data = {status: "disabled", updated_at: "now"}
    } as $model
  }

  response = {disabled: true, id: $input.stage_automation_config_id}
}