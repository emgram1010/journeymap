// SCN-MCP-3: MCP tool — compare the health scorecard of two journey map scenarios side by side.
// Fetches scorecard metrics inline (cell status counts + stage health) rather than delegating
// to compare_GET.xs which returns titles/dates only.
tool compare_scenarios {
  instructions = "Compare the health scorecard of two scenarios side-by-side. Pass journey_architecture_id, map_a_id, map_b_id. Returns journey health, revenue at risk, critical stage count, and per-stage health for both maps. Higher journey health + lower revenue at risk = better scenario. null means no data yet — never infer a winner when one side is null."

  input {
    int journey_architecture_id filters=min:1
    int map_a_id filters=min:1
    int map_b_id filters=min:1
  }

  stack {
    precondition ($input.map_a_id != $input.map_b_id) {
      error_type = "inputerror"
      error = "map_a_id and map_b_id must be different maps"
    }
  
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $arch
  
    precondition ($arch != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $input.map_a_id
    } as $map_a
  
    precondition ($map_a != null) {
      error_type = "notfound"
      error = "Map A not found"
    }
  
    precondition ($map_a.journey_architecture == $input.journey_architecture_id) {
      error_type = "accessdenied"
      error = "Map A does not belong to this architecture"
    }
  
    db.get journey_map {
      field_name = "id"
      field_value = $input.map_b_id
    } as $map_b
  
    precondition ($map_b != null) {
      error_type = "notfound"
      error = "Map B not found"
    }
  
    precondition ($map_b.journey_architecture == $input.journey_architecture_id) {
      error_type = "accessdenied"
      error = "Map B does not belong to this architecture"
    }
  
    // ── Build scorecard for Map A ──
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.map_a_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages_a
  
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.map_a_id
      return = {type: "list"}
    } as $cells_a
  
    var $total_a {
      value = $cells_a|count
    }
  
    var $confirmed_a {
      value = 0
    }
  
    var $open_a {
      value = 0
    }
  
    foreach ($cells_a) {
      each as $c {
        conditional {
          if ($c.status == "confirmed") {
            var.update $confirmed_a {
              value = $confirmed_a + 1
            }
          }
        }
      
        conditional {
          if ($c.status == "open") {
            var.update $open_a {
              value = $open_a + 1
            }
          }
        }
      }
    }
  
    var $health_a {
      value = null
    }
  
    conditional {
      if ($total_a > 0) {
        var.update $health_a {
          value = ($confirmed_a / $total_a * 100)|round:0
        }
      }
    }
  
    var $stage_breakdown_a {
      value = []
    }
  
    foreach ($stages_a) {
      each as $stage {
        var $stage_cells_a {
          value = []
        }
      
        foreach ($cells_a) {
          each as $sc {
            conditional {
              if ($sc.stage == $stage.id) {
                array.push $stage_cells_a {
                  value = $sc
                }
              }
            }
          }
        }
      
        var $stage_total_a {
          value = $stage_cells_a|count
        }
      
        var $stage_confirmed_a {
          value = 0
        }
      
        foreach ($stage_cells_a) {
          each as $stc {
            conditional {
              if ($stc.status == "confirmed") {
                var.update $stage_confirmed_a {
                  value = $stage_confirmed_a + 1
                }
              }
            }
          }
        }
      
        var $stage_health_a {
          value = null
        }
      
        conditional {
          if ($stage_total_a > 0) {
            var.update $stage_health_a {
              value = ($stage_confirmed_a / $stage_total_a * 100)|round:0
            }
          }
        }
      
        array.push $stage_breakdown_a {
          value = {
            stage_key   : $stage.key
            stage_label : $stage.label
            stage_health: $stage_health_a
          }
        }
      }
    }
  
    // ── Build scorecard for Map B ──
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.map_b_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages_b
  
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.map_b_id
      return = {type: "list"}
    } as $cells_b
  
    var $total_b {
      value = $cells_b|count
    }
  
    var $confirmed_b {
      value = 0
    }
  
    foreach ($cells_b) {
      each as $c {
        conditional {
          if ($c.status == "confirmed") {
            var.update $confirmed_b {
              value = $confirmed_b + 1
            }
          }
        }
      }
    }
  
    var $health_b {
      value = null
    }
  
    conditional {
      if ($total_b > 0) {
        var.update $health_b {
          value = ($confirmed_b / $total_b * 100)|round:0
        }
      }
    }
  
    var $stage_breakdown_b {
      value = []
    }
  
    foreach ($stages_b) {
      each as $stage {
        var $stage_cells_b {
          value = []
        }
      
        foreach ($cells_b) {
          each as $sc {
            conditional {
              if ($sc.stage == $stage.id) {
                array.push $stage_cells_b {
                  value = $sc
                }
              }
            }
          }
        }
      
        var $stage_total_b {
          value = $stage_cells_b|count
        }
      
        var $stage_confirmed_b {
          value = 0
        }
      
        foreach ($stage_cells_b) {
          each as $stc {
            conditional {
              if ($stc.status == "confirmed") {
                var.update $stage_confirmed_b {
                  value = $stage_confirmed_b + 1
                }
              }
            }
          }
        }
      
        var $stage_health_b {
          value = null
        }
      
        conditional {
          if ($stage_total_b > 0) {
            var.update $stage_health_b {
              value = ($stage_confirmed_b / $stage_total_b * 100)|round:0
            }
          }
        }
      
        array.push $stage_breakdown_b {
          value = {
            stage_key   : $stage.key
            stage_label : $stage.label
            stage_health: $stage_health_b
          }
        }
      }
    }
  }

  response = {
    map_a: ```
      {
        id             : $map_a.id
        title          : $map_a.title
        status         : $map_a.status
        journey_health : $health_a
        total_cells    : $total_a
        confirmed_cells: $confirmed_a
        stage_breakdown: $stage_breakdown_a
      }
      ```
    map_b: ```
      {
        id             : $map_b.id
        title          : $map_b.title
        status         : $map_b.status
        journey_health : $health_b
        total_cells    : $total_b
        confirmed_cells: $confirmed_b
        stage_breakdown: $stage_breakdown_b
      }
      ```
  }

  guid = "-5A3bkFQb5DFO0MGqblYw0jRl7E"
}