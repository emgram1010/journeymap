// LA-5: MCP tool — Leakage Math API
// Computes per-event, monthly, annual, and 3-year cost of inaction for an L3 atomic map.
// Guard: only runs on map_level = 'atomic'. Returns partial results when fields are missing.
tool calculate_leakage {
  instructions = "Compute leakage math for an L3 atomic journey map. Returns per_event cost, monthly, annual, and 3yr_cost_of_inaction. Requires time_duration on cells and cost_rate on actor lenses. Only valid for map_level='atomic' maps. Returns incomplete_cells[] when fields are missing."

  input {
    int journey_map_id
  }

  stack {
    // 1 — Load the map (need measurement_frequency + map_level guard)
    db.get journey_map {
      field_name  = "id"
      field_value = $input.journey_map_id
    } as $map

    precondition ($map != null) {
      error_type = "notfound"
      error      = "Journey map not found"
    }

    precondition ($map.map_level == "atomic") {
      error_type = "validation"
      error      = "Leakage math requires an atomic (L3) map. This map is level: " ~ ($map.map_level ?? "unset")
    }

    var $frequency {
      value = ($map.measurement_frequency ?? 0)
    }

    // 2 — Load stages, lenses, cells
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort  = {display_order: "asc"}
      return = {type: "list"}
    } as $stages

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $lenses

    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $cells

    // 3 — Accumulate totals
    var $total_per_event { value = 0 }
    var $by_stage        { value = [] }
    var $leakage_cells   { value = [] }
    var $incomplete      { value = [] }

    foreach ($stages) {
      each as $stage {
        var $stage_cost { value = 0 }

        foreach ($cells) {
          each as $cell {
            conditional {
              if ($cell.stage == $stage.id) {

                // Find matching lens for cost_rate
                var $lens_cost_rate  { value = null }
                var $lens_cost_unit  { value = null }

                foreach ($lenses) {
                  each as $lens {
                    conditional {
                      if ($lens.id == $cell.lens) {
                        var.update $lens_cost_rate { value = $lens.cost_rate_value }
                        var.update $lens_cost_unit { value = $lens.cost_rate_unit }
                      }
                    }
                  }
                }

                conditional {
                  if ($cell.time_duration_value != null && $lens_cost_rate != null) {

                    // Normalize time to hours
                    var $time_hours { value = $cell.time_duration_value }
                    conditional {
                      if ($cell.time_duration_unit == "minutes") {
                        var.update $time_hours { value = $cell.time_duration_value / 60 }
                      } elseif ($cell.time_duration_unit == "days") {
                        var.update $time_hours { value = $cell.time_duration_value * 8 }
                      } elseif ($cell.time_duration_unit == "weeks") {
                        var.update $time_hours { value = $cell.time_duration_value * 40 }
                      }
                    }

                    // Normalize cost_rate to per-hour; per_event = flat cost, skip time multiply
                    var $cell_cost { value = 0 }
                    conditional {
                      if ($lens_cost_unit == "per_event") {
                        var.update $cell_cost { value = $lens_cost_rate }
                      } elseif ($lens_cost_unit == "per_minute") {
                        var.update $cell_cost { value = $time_hours * ($lens_cost_rate * 60) }
                      } elseif ($lens_cost_unit == "per_day") {
                        var.update $cell_cost { value = $time_hours * ($lens_cost_rate / 8) }
                      } elseif ($lens_cost_unit == "per_week") {
                        var.update $cell_cost { value = $time_hours * ($lens_cost_rate / 40) }
                      } else {
                        var.update $cell_cost { value = $time_hours * $lens_cost_rate }
                      }
                    }

                    var.update $stage_cost    { value = $stage_cost + $cell_cost }
                    var.update $total_per_event { value = $total_per_event + $cell_cost }

                    array.push $leakage_cells {
                      value = {
                        stage_key   : $stage.key
                        lens_key    : $cell.lens_key
                        metric_label: "cost_per_event"
                        flag        : $cell_cost > 0
                      }
                    }

                  } else {
                    array.push $incomplete {
                      value = {
                        stage_key: $stage.key
                        lens_key : $cell.lens_key
                        missing  : ($cell.time_duration_value == null ? "time_duration" : "cost_rate")
                      }
                    }
                  }
                }
              }
            }
          }
        }

        array.push $by_stage {
          value = {
            stage_key      : $stage.key
            stage_label    : $stage.label
            cost_per_event : $stage_cost
            annual_cost    : $stage_cost * $frequency
          }
        }
      }
    }

    var $annual  { value = $total_per_event * $frequency }
    var $monthly { value = $annual / 12 }
    var $three_yr{ value = $annual * 3 }
  }

  response = {
    journey_map_id       : $input.journey_map_id
    measurement_frequency: $frequency
    per_event            : $total_per_event
    monthly              : $monthly
    annual               : $annual
    3yr_cost_of_inaction : $three_yr
    by_stage             : $by_stage
    leakage_cells        : $leakage_cells
    incomplete_cells     : $incomplete
  }
}
