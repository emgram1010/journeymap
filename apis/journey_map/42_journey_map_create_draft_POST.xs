// v3 — Create a new draft journey map with the default Prototype 2 matrix scaffold.
// owner_user is derived from the authenticated user token — not accepted from client input.
// If journey_architecture_id is provided the map is grouped under that architecture and
// inherits its owner_user and account_id.
query "journey_map/create_draft" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    text title? filters=trim
    enum status? {
      values = ["draft", "active", "archived"]
    }
  
    json settings?
    int account_id? {
      table = "account"
    }
  
    // Optional: group this map under an existing Journey Architecture.
    // When provided, owner_user and account_id are inherited from the architecture.
    int journey_architecture_id?
  }

  stack {
    var $journey_map_title {
      value = "Untitled Journey Map"
    }
  
    var $journey_map_status {
      value = "draft"
    }
  
    // Resolved owner and account — may be overridden by architecture inheritance
    var $resolved_owner_user {
      value = $auth.id
    }
  
    var $resolved_account_id {
      value = $input.account_id
    }
  
    var $resolved_journey_architecture {
      value = null
    }
  
    var $stage_seeds {
      value = []
    }
  
    var $lens_seeds {
      value = []
    }
  
    var $stages {
      value = []
    }
  
    var $lenses {
      value = []
    }
  
    var $cells {
      value = []
    }
  
    conditional {
      if ($input.title != null && $input.title != "") {
        var.update $journey_map_title {
          value = $input.title
        }
      }
    }
  
    conditional {
      if ($input.status != null) {
        var.update $journey_map_status {
          value = $input.status
        }
      }
    }
  
    // Resolve architecture ownership when journey_architecture_id is provided
    conditional {
      if ($input.journey_architecture_id != null) {
        db.get journey_architecture {
          field_name = "id"
          field_value = $input.journey_architecture_id
        } as $architecture
      
        precondition ($architecture != null) {
          error_type = "notfound"
          error = "Journey Architecture not found"
        }
      
        precondition ($architecture.owner_user == $auth.id) {
          error_type = "accessdenied"
          error = "Access denied to this Journey Architecture"
        }
      
        var.update $resolved_owner_user {
          value = $architecture.owner_user
        }
      
        var.update $resolved_account_id {
          value = $architecture.account_id
        }
      
        var.update $resolved_journey_architecture {
          value = $input.journey_architecture_id
        }
      }
    }
  
    array.push $stage_seeds {
      value = {}
        |set:"key":"s1"
        |set:"label":"Stage 1"
        |set:"display_order":1
    }
  
    array.push $stage_seeds {
      value = {}
        |set:"key":"s2"
        |set:"label":"Stage 2"
        |set:"display_order":2
    }
  
    array.push $stage_seeds {
      value = {}
        |set:"key":"s3"
        |set:"label":"Stage 3"
        |set:"display_order":3
    }
  
    array.push $stage_seeds {
      value = {}
        |set:"key":"s4"
        |set:"label":"Stage 4"
        |set:"display_order":4
    }
  
    array.push $stage_seeds {
      value = {}
        |set:"key":"s5"
        |set:"label":"Stage 5"
        |set:"display_order":5
    }
  
    array.push $stage_seeds {
      value = {}
        |set:"key":"s6"
        |set:"label":"Stage 6"
        |set:"display_order":6
    }
  
    array.push $stage_seeds {
      value = {}
        |set:"key":"s7"
        |set:"label":"Stage 7"
        |set:"display_order":7
    }
  
    array.push $stage_seeds {
      value = {}
        |set:"key":"s8"
        |set:"label":"Stage 8"
        |set:"display_order":8
    }
  
    // Minimal scaffold — one lens row only.
    // Users add actor rows (Customer, Internal, AI agent, etc.) via the "Add Row" button.
    array.push $lens_seeds {
      value = {}
        |set:"key":"description"
        |set:"label":"Description"
        |set:"display_order":1
        |set:"description":"Brief summary of what happens at this stage — the core activity."
    }
  
    // Write journey_map — include journey_architecture FK only when present.
    // Two branches keep the data block as an object literal (XanoScript requirement).
    var $journey_map {
      value = null
    }
  
    conditional {
      if ($resolved_journey_architecture != null) {
        db.add journey_map {
          data = {
            created_at          : "now"
            updated_at          : "now"
            title               : $journey_map_title
            status              : $journey_map_status
            owner_user          : $resolved_owner_user
            account_id          : $resolved_account_id
            last_interaction_at : "now"
            settings            : $input.settings
            journey_architecture: $resolved_journey_architecture
          }
        } as $created_map
      
        var.update $journey_map {
          value = $created_map
        }
      }
    
      else {
        db.add journey_map {
          data = {
            created_at         : "now"
            updated_at         : "now"
            title              : $journey_map_title
            status             : $journey_map_status
            owner_user         : $resolved_owner_user
            account_id         : $resolved_account_id
            last_interaction_at: "now"
            settings           : $input.settings
          }
        } as $created_map
      
        var.update $journey_map {
          value = $created_map
        }
      }
    }
  
    foreach ($stage_seeds) {
      each as $stage_seed {
        db.add journey_stage {
          data = {
            created_at   : "now"
            updated_at   : "now"
            journey_map  : $journey_map.id
            key          : $stage_seed.key
            label        : $stage_seed.label
            display_order: $stage_seed.display_order
          }
        } as $stage
      
        array.push $stages {
          value = $stage
        }
      }
    }
  
    foreach ($lens_seeds) {
      each as $lens_seed {
        db.add journey_lens {
          data = {
            created_at   : "now"
            updated_at   : "now"
            journey_map  : $journey_map.id
            key          : $lens_seed.key
            label        : $lens_seed.label
            description  : $lens_seed.description
            display_order: $lens_seed.display_order
          }
        } as $lens
      
        array.push $lenses {
          value = $lens
        }
      }
    }
  
    foreach ($stages) {
      each as $stage {
        foreach ($lenses) {
          each as $lens {
            db.add journey_cell {
              data = {
                created_at : "now"
                updated_at : "now"
                journey_map: $journey_map.id
                stage      : $stage.id
                lens       : $lens.id
                content    : ""
                status     : "open"
                is_locked  : false
              }
            } as $cell
          
            array.push $cells {
              value = $cell
            }
          }
        }
      }
    }
  }

  response = {
    journey_map: $journey_map
    stages     : $stages
    lenses     : $lenses
    cells      : $cells
  }
}