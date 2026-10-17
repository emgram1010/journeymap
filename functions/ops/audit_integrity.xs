// GOV-1 (US-GOV-1-05) — Runtime integrity audit. Read-only.
//
// Xano declares references but does not enforce them: delete a parent
// row and the children keep pointing at an id that no longer exists.
// This walks the real data looking for exactly that, plus the one text
// key in the schema that can silently drift (journey_stage's
// primary_actor_lens, which STAGE-1 will replace with a real reference).
//
// Run daily by tasks/ops_integrity_audit.xs, which logs the result as a
// single event so the Health page can show it. Zero findings on clean
// data is the expected state.
//
// SCOPE: only the tables that exist today. Later epics add their own
// checks here as their tables land — work_task against its pinned
// version, planner_task_work_task orphans, log rows whose task is
// missing, publications whose hash no longer matches, a job whose
// stored status disagrees with its tasks. Each is listed in
// EPIC-GOV-1 US-GOV-1-05 and should be added by the epic that creates
// the table, not retrofitted later.
//
// STYLE NOTE (learned the hard way, 2026-10-13): a pipe nested inside a
// filter argument — `$map|get:($row.id|to_text):null` — parses fine but
// fails at runtime with "Invalid expression". Every `|to_text` here is
// therefore hoisted into its own `var` first, and only plain variables
// are passed as filter arguments. Same rule as the rest of CLAUDE.md's
// verified constraints: no paging, no array indexing, no array.map.
function "ops/audit_integrity" {
  description = "Walks existing data for orphaned references and drifted keys. Read-only; returns findings."

  input {
    int max_detail?=100 filters=min:1|max:500 {
      description = "How many findings to return in full. The counts are always complete."
    }
  }

  stack {
    db.query journey_map {
      return = {type: "list"}
    } as $maps

    db.query journey_lens {
      return = {type: "list"}
    } as $lenses

    db.query journey_stage {
      return = {type: "list"}
    } as $stages

    db.query journey_cell {
      return = {type: "list"}
    } as $cells

    db.query account {
      return = {type: "list"}
    } as $accounts

    db.query account_feature_flag {
      return = {type: "list"}
    } as $flags

    var $map_ids {
      value = {}
    }

    foreach ($maps) {
      each as $row {
        var $map_id_key {
          value = $row.id|to_text
        }

        var.update $map_ids {
          value = $map_ids|set:$map_id_key:true
        }
      }
    }

    var $lens_ids {
      value = {}
    }

    var $map_lens_keys {
      value = {}
    }

    foreach ($lenses) {
      each as $row {
        var $lens_id_key {
          value = $row.id|to_text
        }

        var.update $lens_ids {
          value = $lens_ids|set:$lens_id_key:true
        }

        var $lens_map_text {
          value = $row.journey_map|to_text
        }

        var $lens_key_text {
          value = $row.key ?? ""
        }

        var $owner_key {
          value = $lens_map_text ~ "::" ~ $lens_key_text
        }

        var.update $map_lens_keys {
          value = $map_lens_keys|set:$owner_key:true
        }
      }
    }

    var $stage_ids {
      value = {}
    }

    foreach ($stages) {
      each as $row {
        var $stage_id_key {
          value = $row.id|to_text
        }

        var.update $stage_ids {
          value = $stage_ids|set:$stage_id_key:true
        }
      }
    }

    var $account_ids {
      value = {}
    }

    foreach ($accounts) {
      each as $row {
        var $account_id_key {
          value = $row.id|to_text
        }

        var.update $account_ids {
          value = $account_ids|set:$account_id_key:true
        }
      }
    }

    var $findings {
      value = []
    }

    var $finding_count {
      value = 0
    }

    var $c_cell_map {
      value = 0
    }

    var $c_cell_stage {
      value = 0
    }

    var $c_cell_lens {
      value = 0
    }

    var $c_stage_map {
      value = 0
    }

    var $c_stage_owner {
      value = 0
    }

    var $c_lens_map {
      value = 0
    }

    var $c_flag_account {
      value = 0
    }

    // ── journey_cell: map, stage and lens must all still exist ────────
    foreach ($cells) {
      each as $cell {
        var $cell_map_key {
          value = $cell.journey_map|to_text
        }

        var $cell_map_hit {
          value = $map_ids|get:$cell_map_key:null
        }

        conditional {
          if ($cell.journey_map != 0 && $cell_map_hit == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_cell_map {
              value = $c_cell_map + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"journey_cell.journey_map"|set:"entity_type":"journey_cell"|set:"entity_id":$cell.id|set:"detail":("points at journey_map " ~ $cell_map_key ~ ", which does not exist")
                }
              }
            }
          }
        }

        var $cell_stage_key {
          value = $cell.stage|to_text
        }

        var $cell_stage_hit {
          value = $stage_ids|get:$cell_stage_key:null
        }

        conditional {
          if ($cell.stage != 0 && $cell_stage_hit == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_cell_stage {
              value = $c_cell_stage + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"journey_cell.stage"|set:"entity_type":"journey_cell"|set:"entity_id":$cell.id|set:"detail":("points at journey_stage " ~ $cell_stage_key ~ ", which does not exist")
                }
              }
            }
          }
        }

        var $cell_lens_key {
          value = $cell.lens|to_text
        }

        var $cell_lens_hit {
          value = $lens_ids|get:$cell_lens_key:null
        }

        conditional {
          if ($cell.lens != 0 && $cell_lens_hit == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_cell_lens {
              value = $c_cell_lens + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"journey_cell.lens"|set:"entity_type":"journey_cell"|set:"entity_id":$cell.id|set:"detail":("points at journey_lens " ~ $cell_lens_key ~ ", which does not exist")
                }
              }
            }
          }
        }
      }
    }

    // ── journey_stage: map must exist, and the owner text key must
    //    resolve to a lens IN THAT MAP (the key STAGE-1 replaces) ─────
    foreach ($stages) {
      each as $stage {
        var $stage_map_key {
          value = $stage.journey_map|to_text
        }

        var $stage_map_hit {
          value = $map_ids|get:$stage_map_key:null
        }

        conditional {
          if ($stage.journey_map != 0 && $stage_map_hit == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_stage_map {
              value = $c_stage_map + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"journey_stage.journey_map"|set:"entity_type":"journey_stage"|set:"entity_id":$stage.id|set:"detail":("points at journey_map " ~ $stage_map_key ~ ", which does not exist")
                }
              }
            }
          }
        }

        var $stage_owner_text {
          value = $stage.primary_actor_lens ?? ""
        }

        var $stage_owner_key {
          value = $stage_map_key ~ "::" ~ $stage_owner_text
        }

        var $stage_owner_hit {
          value = $map_lens_keys|get:$stage_owner_key:null
        }

        conditional {
          if ($stage_owner_text != "" && $stage_owner_hit == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_stage_owner {
              value = $c_stage_owner + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"journey_stage.primary_actor_lens"|set:"entity_type":"journey_stage"|set:"entity_id":$stage.id|set:"detail":("owner key " ~ $stage_owner_text ~ " matches no lens in map " ~ $stage_map_key)
                }
              }
            }
          }
        }
      }
    }

    // ── journey_lens: the map must exist ──────────────────────────────
    foreach ($lenses) {
      each as $lens {
        var $lens_map_key2 {
          value = $lens.journey_map|to_text
        }

        var $lens_map_hit {
          value = $map_ids|get:$lens_map_key2:null
        }

        conditional {
          if ($lens.journey_map != 0 && $lens_map_hit == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_lens_map {
              value = $c_lens_map + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"journey_lens.journey_map"|set:"entity_type":"journey_lens"|set:"entity_id":$lens.id|set:"detail":("points at journey_map " ~ $lens_map_key2 ~ ", which does not exist")
                }
              }
            }
          }
        }
      }
    }

    // ── account_feature_flag: the account must exist ──────────────────
    foreach ($flags) {
      each as $flag {
        var $flag_account_key {
          value = $flag.account_id|to_text
        }

        var $flag_account_hit {
          value = $account_ids|get:$flag_account_key:null
        }

        conditional {
          if ($flag.account_id != 0 && $flag_account_hit == null) {
            var.update $finding_count {
              value = $finding_count + 1
            }

            var.update $c_flag_account {
              value = $c_flag_account + 1
            }

            conditional {
              if (($findings|count) < $input.max_detail) {
                array.push $findings {
                  value = {}|set:"check":"account_feature_flag.account_id"|set:"entity_type":"account_feature_flag"|set:"entity_id":$flag.id|set:"detail":("points at account " ~ $flag_account_key ~ ", which does not exist")
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    finding_count: $finding_count
    findings     : $findings
    truncated    : ($finding_count > ($findings|count))
    counts_by_check: {
      journey_cell_journey_map         : $c_cell_map
      journey_cell_stage               : $c_cell_stage
      journey_cell_lens                : $c_cell_lens
      journey_stage_journey_map        : $c_stage_map
      journey_stage_primary_actor_lens : $c_stage_owner
      journey_lens_journey_map         : $c_lens_map
      account_feature_flag_account_id  : $c_flag_account
    }
    rows_checked : {
      journey_cell        : ($cells|count)
      journey_stage       : ($stages|count)
      journey_lens        : ($lenses|count)
      account_feature_flag: ($flags|count)
    }
  }
}
