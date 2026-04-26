// Scorecard rollup: aggregates metrics and financial lens data for a journey map.
// Returns per-stage health + map-level health + financial totals.
query "journey_map/{journey_map_id}/scorecard" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map
  
    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.template_key == "metrics-v1"
      return = {type: "single"}
    } as $metrics_lens
  
    conditional {
      if ($metrics_lens == null) {
        db.query journey_lens {
          where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.actor_type == "metrics"
          return = {type: "single"}
        } as $metrics_lens
      }
    }
  
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.template_key == "financial-v1"
      return = {type: "single"}
    } as $financial_lens
  
    var $stage_results {
      value = []
    }
  
    var $health_sum {
      value = 0
    }
  
    var $health_count {
      value = 0
    }
  
    var $populated_count {
      value = 0
    }
  
    var $total_cost_to_serve {
      value = 0
    }
  
    var $total_revenue_at_risk {
      value = 0
    }
  
    var $total_automation_savings {
      value = 0
    }
  
    var $total_upsell_opportunity {
      value = 0
    }
  
    var $map_health {
      value = null
    }
  
    var $map_hl {
      value = null
    }
  
    foreach ($stages) {
      each as $stage {
        var $stage_health {
          value = null
        }
      
        var $stage_cell_pop {
          value = false
        }
      
        var $hl {
          value = null
        }
      
        var $mc {
          value = null
        }
      
        var $af {
          value = null
        }
      
        var $sh {
          value = null
        }
      
        var $csat {
          value = null
        }
      
        var $cr {
          value = null
        }
      
        var $fc {
          value = null
        }
      
        var $faf {
          value = null
        }
      
        var $cts {
          value = null
        }
      
        var $rar {
          value = null
        }
      
        var $asy {
          value = null
        }
      
        var $uop {
          value = null
        }
      
        conditional {
          if ($metrics_lens != null) {
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $metrics_lens.id
              return = {type: "single"}
            } as $mc
          
            conditional {
              if ($mc != null && $mc.actor_fields != null) {
                var.update $af {
                  value = $mc.actor_fields
                }
              
                var.update $sh {
                  value = $af|get:"stage_health"
                }
              
                var.update $csat {
                  value = $af|get:"csat_score"
                }
              
                var.update $cr {
                  value = $af|get:"completion_rate"
                }
              
                conditional {
                  if ($sh != null) {
                    var.update $stage_health {
                      value = $sh|to_text|to_decimal
                    }
                  
                    var.update $stage_cell_pop {
                      value = true
                    }
                  }
                }
              
                conditional {
                  if ($csat != null || $cr != null) {
                    var.update $stage_cell_pop {
                      value = true
                    }
                  }
                }
              }
            }
          }
        }
      
        conditional {
          if ($stage_health != null && $stage_health >= 8) {
            var.update $hl {
              value = "healthy"
            }
          }
        }
      
        conditional {
          if ($stage_health != null && $stage_health >= 5 && $stage_health < 8) {
            var.update $hl {
              value = "at_risk"
            }
          }
        }
      
        conditional {
          if ($stage_health != null && $stage_health < 5) {
            var.update $hl {
              value = "critical"
            }
          }
        }
      
        conditional {
          if ($stage_health != null) {
            var.update $health_sum {
              value = $health_sum + $stage_health
            }
          
            var.update $health_count {
              value = $health_count + 1
            }
          }
        }
      
        conditional {
          if ($stage_cell_pop) {
            var.update $populated_count {
              value = $populated_count + 1
            }
          }
        }
      
        var.update $stage_results {
          value = $stage_results
            |push:```
              {
                stage_id      : $stage.id
                stage_key     : $stage.key
                stage_label   : $stage.label
                health        : $stage_health
                health_label  : $hl
                cell_populated: $stage_cell_pop
              }
              ```
        }
      
        conditional {
          if ($financial_lens != null) {
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.journey_map_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $financial_lens.id
              return = {type: "single"}
            } as $fc
          
            conditional {
              if ($fc != null && $fc.actor_fields != null) {
                var.update $faf {
                  value = $fc.actor_fields
                }
              
                var.update $cts {
                  value = $faf|get:"cost_to_serve"
                }
              
                var.update $rar {
                  value = $faf|get:"revenue_at_risk"
                }
              
                var.update $asy {
                  value = $faf|get:"automation_savings"
                }
              
                var.update $uop {
                  value = $faf|get:"upsell_opportunity"
                }
              
                conditional {
                  if ($cts != null) {
                    var.update $total_cost_to_serve {
                      value = $total_cost_to_serve + ($cts|to_text|to_decimal)
                    }
                  }
                }
              
                conditional {
                  if ($rar != null) {
                    var.update $total_revenue_at_risk {
                      value = $total_revenue_at_risk + ($rar|to_text|to_decimal)
                    }
                  }
                }
              
                conditional {
                  if ($asy != null) {
                    var.update $total_automation_savings {
                      value = $total_automation_savings + ($asy|to_text|to_decimal)
                    }
                  }
                }
              
                conditional {
                  if ($uop != null) {
                    var.update $total_upsell_opportunity {
                      value = $total_upsell_opportunity + ($uop|to_text|to_decimal)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  
    conditional {
      if ($health_count > 0) {
        var.update $map_health {
          value = ($health_sum / $health_count)|round:1
        }
      }
    }
  
    conditional {
      if ($map_health != null && $map_health >= 8) {
        var.update $map_hl {
          value = "healthy"
        }
      }
    }
  
    conditional {
      if ($map_health != null && $map_health >= 5 && $map_health < 8) {
        var.update $map_hl {
          value = "at_risk"
        }
      }
    }
  
    conditional {
      if ($map_health != null && $map_health < 5) {
        var.update $map_hl {
          value = "critical"
        }
      }
    }
  
    var $scorecard {
      value = {
        metrics_rollup  : {
          map_health     : $map_health
          map_hl         : $map_hl
          stages         : $stage_results
          populated_count: $populated_count
          total_count    : ($stages|count)
        }
        financial_rollup: {
          total_cost_to_serve      : $total_cost_to_serve
          total_revenue_at_risk    : $total_revenue_at_risk
          total_automation_savings : $total_automation_savings
          total_upsell_opportunity : $total_upsell_opportunity
        }
      }
    }
  }

  response = $scorecard
}