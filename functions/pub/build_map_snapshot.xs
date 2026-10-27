// PUB-1 (US-PUB-1-03) — Reads a map's live work definition and returns
// the frozen snapshot shape that gets stored on a version row and hashed
// by pub/canonical_hash.
//
// This is also what pub/evaluate_readiness runs over, so the gate and the
// frozen version can never disagree about what they looked at.
//
// Array order is fixed here because the canonical hash takes array order
// as given — unstable ordering would make the same map hash differently
// and break stale detection. Stages and rows go by display_order then id;
// links by id.
//
// CELLS ARE ORDERED BY KEY, NOT BY ID (changed in the PUB-1 review pass).
// They used to come straight out of a `sort = {stage: "asc", lens: "asc"}`
// query, i.e. ordered by database id. That made the hash depend on ids
// rather than on content: delete a row and re-add it with the same key and
// it gets a new, higher id, so the cells re-sort and the map hashes
// differently even though nothing a user can see has changed. Emitting them
// by walking the already-ordered stages × rows means the order follows the
// definition itself, which is what "same content, same hash" requires.
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
      return = {type: "list"}
    } as $cell_rows

    var $cell_location_by_id {
      value = {}
    }

    // Prepared cells are parked in a map keyed "stage_key\0lens_key" and
    // emitted in definition order further down, so the output order never
    // depends on row ids. NUL is the separator because it cannot appear in
    // a key.
    var $prepared_cell_by_slot {
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

                var $slot_key {
                  value = $cell_stage_key ~ "\u0000" ~ $cell_lens_key
                }

                var.update $prepared_cell_by_slot {
                  value = $prepared_cell_by_slot|set:$slot_key:({}|set:"stage_key":$cell_stage_key|set:"lens_key":$cell_lens_key|set:"task":$task|set:"done_when":$done_when|set:"duration_minutes":$duration_result.minutes)
                }
              }
            }
          }
        }
      }
    }

    // Emit in definition order: every stage, and within it every row, in the
    // order the map itself presents them.
    var $cells {
      value = []
    }

    foreach ($stages) {
      each as $ordered_stage {
        foreach ($lenses) {
          each as $ordered_lens {
            var $lookup_slot {
              value = $ordered_stage.key ~ "\u0000" ~ $ordered_lens.key
            }

            var $prepared_cell {
              value = $prepared_cell_by_slot|get:$lookup_slot:null
            }

            conditional {
              if ($prepared_cell != null) {
                array.push $cells {
                  value = $prepared_cell
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

    // ── RATE-1 (US-RATE-1-02) — Items row: scaling + rates, schema v2 ──
    // D-1, DECIDED AGAINST THE DRAFT DEFAULT: schema_version becomes 2 only
    // when the map HAS an Items row. Bumping every snapshot would make
    // endpoint 521's stale check (live v2 hash vs. stored v1 hash) report
    // "unpublished changes" on every map ever published, the moment this
    // shipped, with nothing changed. A map with no Items row has no rates,
    // so v1 already says everything true about it.
    var $schema_version {
      value = 1
    }

    var $scaling {
      value = []
    }

    var $rates {
      value = []
    }

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.template_key == "items-v1"
      return = {type: "single"}
    } as $items_lens

    conditional {
      if ($items_lens != null) {
        var.update $schema_version {
          value = 2
        }

        db.query journey_cell {
          where = $db.journey_cell.lens == $items_lens.id
          return = {type: "list"}
        } as $items_cell_rows

        // Seed every stage as per_order with no lines, so a stage whose
        // Items cell is missing still gets a deterministic entry and the
        // lookup below never sees an absent key (|get with a variable key
        // ignores its default — CLAUDE.md).
        var $items_fields_by_stage {
          value = {}
        }

        foreach ($stages) {
          each as $seed_stage {
            var.update $items_fields_by_stage {
              value = $items_fields_by_stage|set:$seed_stage.key:{scales_with: "per_order", lines: []}
            }
          }
        }

        foreach ($items_cell_rows) {
          each as $items_cell_row {
            var $ic_stage_id_key {
              value = $items_cell_row.stage|to_text
            }

            var $ic_stage_key {
              value = $stage_key_by_id|get:$ic_stage_id_key:null
            }

            conditional {
              if ($ic_stage_key != null) {
                var.update $items_fields_by_stage {
                  value = $items_fields_by_stage|set:$ic_stage_key:($items_cell_row.actor_fields ?? {scales_with: "per_order", lines: []})
                }
              }
            }
          }
        }

        // Stage display order, then quantity_key, then method_key —
        // content order, never id order (PUB-1's lesson). A SPACE
        // separates the two sort keys: keys are [a-z0-9-] and trimmed, so
        // a space sorts below every key character and ("a", "z") comes
        // before ("a-b", "c"). NOT "\u0000" — confirmed live that it
        // sorted AFTER "-" (put "item-2" ahead of "item"), so XanoScript
        // does not turn it into a NUL byte.
        foreach ($stages) {
          each as $rate_stage {
            var $stage_fields {
              value = $items_fields_by_stage|get:$rate_stage.key:null
            }

            array.push $scaling {
              value = {
                stage_key  : $rate_stage.key
                scales_with: $stage_fields.scales_with ?? "per_order"
              }
            }

            var $stage_lines {
              value = $stage_fields.lines ?? []
            }

            var $stage_rates {
              value = []
            }

            foreach ($stage_lines) {
              each as $stage_line {
                // An EMPTY minutes box is "no rate", not a rate of 0 — it is
                // omitted here and surfaced by readiness / EST-1. Tested as
                // text because `0 == null` is true in this engine
                // (CLAUDE.md), and 0 minutes is a legitimate rate.
                conditional {
                  if ((($stage_line.minutes_per_unit ?? "")|to_text) != "") {
                    array.push $stage_rates {
                      value = {
                        sort_key        : ($stage_line.item_key ?? "") ~ " " ~ ($stage_line.method_key ?? "")
                        stage_key       : $rate_stage.key
                        quantity_key    : $stage_line.item_key ?? ""
                        method_key      : $stage_line.method_key ?? ""
                        minutes_per_unit: ($stage_line.minutes_per_unit|number_format:2:".":"")|to_decimal
                        source          : "seed"
                      }
                    }
                  }
                }
              }
            }

            var $sorted_stage_rates {
              value = $stage_rates|sort:"sort_key":"text":true
            }

            foreach ($sorted_stage_rates) {
              each as $sorted_rate {
                array.push $rates {
                  value = {
                    stage_key       : $sorted_rate.stage_key
                    quantity_key    : $sorted_rate.quantity_key
                    method_key      : $sorted_rate.method_key
                    minutes_per_unit: $sorted_rate.minutes_per_unit
                    source          : $sorted_rate.source
                  }
                }
              }
            }
          }
        }
      }
    }

    var $snapshot {
      value = {
        schema_version: $schema_version
        title         : $map.title ?? ""
        stages        : $stages
        lenses        : $lenses
        cells         : $cells
        links         : $links
      }
    }

    // v1 snapshots keep exactly their old shape — no empty new keys.
    conditional {
      if ($schema_version == 2) {
        var.update $snapshot {
          value = $snapshot|set:"scaling":$scaling|set:"rates":$rates
        }
      }
    }
  }

  response = {snapshot: $snapshot}
}
