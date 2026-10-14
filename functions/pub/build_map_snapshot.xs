// PUB-1 (US-PUB-1-03) — Reads a map's live work definition and returns
// the frozen snapshot shape that gets stored on a version row and hashed
// by pub/canonical_hash.
//
// This is also what pub/evaluate_readiness runs over, so the gate and the
// frozen version can never disagree about what they looked at.
//
// Array order is fixed here (stages and rows by display_order then id,
// cells by stage then row, links by id) because the canonical hash takes
// array order as given — unstable ordering would make the same map hash
// differently on every publish and break stale detection.
//
// Shape mirrors webapp/protype-2/src/versionHash.ts's MapSnapshot.
function "pub/build_map_snapshot" {
  description = "Builds the frozen work-definition snapshot for one map: title, stages, rows, work cells, links."

  input {
    int journey_map_id filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $map

    precondition ($map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      sort = {display_order: "asc", id: "asc"}
      return = {type: "list"}
    } as $stage_rows

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      sort = {display_order: "asc", id: "asc"}
      return = {type: "list"}
    } as $lens_rows

    // journey_stage_owner has no journey_map column (STAGE-1's side-table
    // workaround), so it is read whole and matched by stage id. The table
    // holds one row per OWNED stage across all maps — small by design.
    db.query journey_stage_owner {
      return = {type: "list"}
    } as $owner_rows

    var $owner_by_stage {
      value = {}
    }

    foreach ($owner_rows) {
      each as $owner_row {
        var $owner_stage_key {
          value = $owner_row.journey_stage|to_text
        }

        var.update $owner_by_stage {
          value = $owner_by_stage|set:$owner_stage_key:$owner_row.owner_lens_id
        }
      }
    }

    // ── Rows (lenses) ────────────────────────────────────────────────────
    var $lenses {
      value = []
    }

    var $lens_key_by_id {
      value = {}
    }

    var $lens_works_by_id {
      value = {}
    }

    foreach ($lens_rows) {
      each as $lens_row {
        // Reuses STAGE-1's resolver so the "does this row do planned work?"
        // rule lives in exactly one place on the backend.
        function.run "does_planned_work" {
          input = {
            journey_lens_id: $lens_row.id
            actor_type     : $lens_row.actor_type
          }
        } as $work_result

        var $lens_id_key {
          value = $lens_row.id|to_text
        }

        var $lens_key {
          value = $lens_row.key ?? ""
        }

        var.update $lens_key_by_id {
          value = $lens_key_by_id|set:$lens_id_key:$lens_key
        }

        var.update $lens_works_by_id {
          value = $lens_works_by_id|set:$lens_id_key:$work_result.does_planned_work
        }

        array.push $lenses {
          value = {
            key              : $lens_key
            label            : $lens_row.label ?? ""
            actor_type       : $lens_row.actor_type ?? ""
            does_planned_work: $work_result.does_planned_work
          }
        }
      }
    }

    // ── Stages ───────────────────────────────────────────────────────────
    var $stages {
      value = []
    }

    var $stage_key_by_id {
      value = {}
    }

    foreach ($stage_rows) {
      each as $stage_row {
        var $stage_id_key {
          value = $stage_row.id|to_text
        }

        var $stage_key {
          value = $stage_row.key ?? ""
        }

        var.update $stage_key_by_id {
          value = $stage_key_by_id|set:$stage_id_key:$stage_key
        }

        var $owner_lens_id {
          value = $owner_by_stage|get:$stage_id_key:null
        }

        var $owner_lens_key {
          value = null
        }

        conditional {
          if ($owner_lens_id != null) {
            var $owner_lens_id_key {
              value = $owner_lens_id|to_text
            }

            var.update $owner_lens_key {
              value = $lens_key_by_id|get:$owner_lens_id_key:null
            }
          }
        }

        array.push $stages {
          value = {
            key           : $stage_key
            label         : $stage_row.label ?? ""
            owner_lens_key: $owner_lens_key
          }
        }
      }
    }

    // ── Cells ────────────────────────────────────────────────────────────
    db.query journey_cell {
      where = $db.journey_cell.journey_map == $input.journey_map_id
      sort = {stage: "asc", lens: "asc"}
      return = {type: "list"}
    } as $cell_rows

    var $cells {
      value = []
    }

    var $cell_location_by_id {
      value = {}
    }

    foreach ($cell_rows) {
      each as $cell_row {
        var $cell_stage_id_key {
          value = $cell_row.stage|to_text
        }

        var $cell_lens_id_key {
          value = $cell_row.lens|to_text
        }

        var $cell_stage_key {
          value = $stage_key_by_id|get:$cell_stage_id_key:null
        }

        var $cell_lens_key {
          value = $lens_key_by_id|get:$cell_lens_id_key:null
        }

        var $cell_id_key {
          value = $cell_row.id|to_text
        }

        // Every cell gets a location entry — links hang off cells that are
        // not necessarily work cells.
        conditional {
          if ($cell_stage_key != null && $cell_lens_key != null) {
            var.update $cell_location_by_id {
              value = $cell_location_by_id|set:$cell_id_key:({}|set:"stage_key":$cell_stage_key|set:"lens_key":$cell_lens_key)
            }
          }
        }

        var $cell_does_work {
          value = $lens_works_by_id|get:$cell_lens_id_key:false
        }

        conditional {
          if ($cell_stage_key != null && $cell_lens_key != null && $cell_does_work == true) {
            // "Touched" matches AUTH-1's cellHasAnyContent exactly: freeform
            // content or ANY actor field. Duration is deliberately NOT a
            // signal — an untouched decimal column reads as 0, not null, so
            // it would mark every empty cell as started (AUTH-1 bug #4).
            var $has_content {
              value = ($cell_row.content != null && $cell_row.content != "")
            }

            conditional {
              if ($cell_row.actor_fields != null) {
                var $field_values {
                  value = $cell_row.actor_fields|values
                }

                foreach ($field_values) {
                  each as $field_value {
                    conditional {
                      if ($field_value != null) {
                        var $field_text {
                          value = $field_value|to_text|trim
                        }

                        conditional {
                          if ($field_text != "") {
                            var.update $has_content {
                              value = true
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
              if ($has_content == true) {
                var $task {
                  value = $cell_row.actor_fields.task_objective ?? null
                }

                var $done_when {
                  value = $cell_row.actor_fields.success_criteria ?? null
                }

                // TIME-1's converter, passed as text so "not set" and "0"
                // stay distinguishable (see duration_to_minutes' header).
                var $duration_text {
                  value = ""
                }

                conditional {
                  if ($cell_row.time_duration_value != null) {
                    var.update $duration_text {
                      value = $cell_row.time_duration_value|to_text
                    }
                  }
                }

                function.run "duration_to_minutes" {
                  input = {
                    value_text: $duration_text
                    unit      : $cell_row.time_duration_unit
                  }
                } as $duration_result

                array.push $cells {
                  value = {
                    stage_key       : $cell_stage_key
                    lens_key        : $cell_lens_key
                    task            : $task
                    done_when       : $done_when
                    duration_minutes: $duration_result.minutes
                  }
                }
              }
            }
          }
        }
      }
    }

    // ── Links ────────────────────────────────────────────────────────────
    db.query journey_link {
      where = $db.journey_link.source_map == $input.journey_map_id
      sort = {id: "asc"}
      return = {type: "list"}
    } as $link_rows

    var $links {
      value = []
    }

    foreach ($link_rows) {
      each as $link_row {
        var $link_cell_key {
          value = $link_row.source_cell|to_text
        }

        var $link_location {
          value = $cell_location_by_id|get:$link_cell_key:null
        }

        conditional {
          if ($link_location != null) {
            array.push $links {
              value = {
                stage_key    : $link_location.stage_key
                lens_key     : $link_location.lens_key
                link_type    : $link_row.link_type ?? ""
                target_map_id: $link_row.target_map ?? 0
              }
            }
          }
        }
      }
    }

    var $snapshot {
      value = {
        schema_version: 1
        title         : $map.title ?? ""
        stages        : $stages
        lenses        : $lenses
        cells         : $cells
        links         : $links
      }
    }
  }

  response = {snapshot: $snapshot}
}
