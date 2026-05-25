// IL-00-02: MCP tool — create a journey map draft with default scaffold.
// Maps to POST /journey_map/create_draft
tool create_journey_map {
  instructions = "Create a new journey map draft. Pass title (required), journey_architecture_id (optional — groups under an architecture), and intent (optional: sop | automation | hybrid). Returns the map bundle with id, stages, lenses, and cells."

  input {
    text title filters=trim
    int journey_architecture_id?
    enum intent? {
      values = ["sop", "automation", "hybrid"]
    }
  }

  stack {
    precondition ($input.title != null && $input.title != "") {
      error_type = "inputerror"
      error = "title is required"
    }
  
    // Resolve architecture ownership if provided
    var $resolved_architecture {
      value = null
    }
  
    var $resolved_account_id {
      value = null
    }
  
    conditional {
      if ($input.journey_architecture_id != null) {
        db.get journey_architecture {
          field_name = "id"
          field_value = $input.journey_architecture_id
        } as $arch
      
        precondition ($arch != null) {
          error_type = "notfound"
          error = "Journey Architecture not found"
        }
      
        var.update $resolved_architecture {
          value = $input.journey_architecture_id
        }
      
        var.update $resolved_account_id {
          value = $arch.account_id
        }
      }
    }
  
    // Create the map
    db.add journey_map {
      data = {
        created_at          : "now"
        updated_at          : "now"
        title               : $input.title
        status              : "draft"
        last_interaction_at : "now"
        journey_architecture: $resolved_architecture
        account_id          : $resolved_account_id
        intent              : $input.intent
      }
    } as $journey_map
  
    // Seed default stages s1–s8
    var $stages {
      value = []
    }
  
    var $stage_idx {
      value = 1
    }
  
    foreach ([1, 2, 3, 4, 5, 6, 7, 8]) {
      each as $n {
        db.add journey_stage {
          data = {
            created_at   : "now"
            updated_at   : "now"
            journey_map  : $journey_map.id
            key          : "s" ~ ($n|to_text)
            label        : "Stage " ~ ($n|to_text)
            display_order: $n
          }
        } as $stage
      
        array.push $stages {
          value = $stage
        }
      }
    }
  
    // Seed default description lens
    db.add journey_lens {
      data = {
        created_at   : "now"
        updated_at   : "now"
        journey_map  : $journey_map.id
        key          : "description"
        label        : "Description"
        display_order: 1
        description  : "Brief summary of what happens at this stage."
      }
    } as $lens
  
    var $lenses {
      value = [$lens]
    }
  
    // Create cells for each stage × lens
    var $cells {
      value = []
    }
  
    foreach ($stages) {
      each as $stg {
        db.add journey_cell {
          data = {
            created_at : "now"
            updated_at : "now"
            journey_map: $journey_map.id
            stage      : $stg.id
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

  response = {
    journey_map: $journey_map
    stages     : $stages
    lenses     : $lenses
    cells      : $cells
  }
}