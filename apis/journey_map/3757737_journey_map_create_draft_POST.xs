// Create a new draft journey map with the default Prototype 2 matrix scaffold.
query "journey_map/create_draft" verb=POST {
  api_group = "journey-map"

  input {
    text title? filters=trim
    enum status? {
      values = ["draft", "active", "archived"]
    }
  
    json settings?
    int owner_user? {
      table = "user"
    }
  
    int account_id? {
      table = "account"
    }
  }

  stack {
    var $journey_map_title {
      value = "Untitled Journey Map"
    }
  
    var $journey_map_status {
      value = "draft"
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
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"description"
        |set:"label":"Description"
        |set:"display_order":1
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"customer"
        |set:"label":"Customer"
        |set:"display_order":2
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"owner"
        |set:"label":"Primary Owner"
        |set:"display_order":3
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"supporting"
        |set:"label":"Supporting Roles"
        |set:"display_order":4
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"painpoint"
        |set:"label":"Top Pain Point"
        |set:"display_order":5
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"variable"
        |set:"label":"Key Variable"
        |set:"display_order":6
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"risk"
        |set:"label":"Cascade Risk"
        |set:"display_order":7
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"trigger"
        |set:"label":"Escalation Trigger"
        |set:"display_order":8
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"notifications"
        |set:"label":"Notifications"
        |set:"display_order":9
    }
  
    array.push $lens_seeds {
      value = {}
        |set:"key":"systems"
        |set:"label":"Systems / Tools"
        |set:"display_order":10
    }
  
    db.add journey_map {
      data = {
        created_at         : "now"
        updated_at         : "now"
        title              : $journey_map_title
        status             : $journey_map_status
        owner_user         : $input.owner_user
        account_id         : $input.account_id
        last_interaction_at: "now"
        settings           : $input.settings
      }
    } as $journey_map
  
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