// List all journey maps (scenarios) within a Journey Architecture.
// Returns each scenario with owner name resolved from the user table.
// Returns 403 if requesting user does not own the architecture.
// Returns [] (empty array) when no scenarios exist yet.
query "journey_architecture/{journey_architecture_id}/scenarios" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
  }

  stack {
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
  
    db.query journey_map {
      where = $db.journey_map.journey_architecture == $input.journey_architecture_id
      sort = {updated_at: "desc"}
      return = {type: "list"}
    } as $maps
  
    var $result {
      value = []
    }
  
    foreach ($maps) {
      each as $map {
        var $owner_name {
          value = "Unknown"
        }
      
        conditional {
          if ($map.owner_user != null) {
            db.get user {
              field_name = "id"
              field_value = $map.owner_user
            } as $owner
          
            conditional {
              if ($owner != null && $owner.name != null && $owner.name != "") {
                var.update $owner_name {
                  value = $owner.name
                }
              }
            }
          
            conditional {
              if ($owner != null && ($owner.name == null || $owner.name == "") && $owner.email != null) {
                var.update $owner_name {
                  value = $owner.email
                }
              }
            }
          }
        }
      
        var.update $result {
          value = $result
            |push:```
              {
                id                 : $map.id
                title              : $map.title
                owner_name         : $owner_name
                created_at         : $map.created_at
                updated_at         : $map.updated_at
                cloned_from_map_id : $map.cloned_from_map_id
              }
              ```
        }
      }
    }
  }

  response = $result
}