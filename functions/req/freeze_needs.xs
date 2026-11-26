// REQ-1 story 05 — Publish version freezes what each step needs, WITH the version. WRITE-ONLY helper called by Publish version (endpoint 201) INSIDE its existing db.transaction, right after the version row is written: plain database writes only, so a failed publish leaves no needs, and no version without them. It reads the map's draft needs (journey_cell_requirement), turns each step into its STAGE KEY and ROW KEY (never the cell id: a recreated cell id would break the link, while the keys never change after creation and are the same keys a job's step uses), and writes one journey_map_version_requirement row per need. It also writes ONE journey_map_version_needs_hash row (count + sha256 from req/needs_hash). A map with NO needs writes nothing at all: no rows, no hash row, so its publish is exactly what it was before. A need whose step has lost its stage or row is not frozen (an orphan). An archived requirement is frozen as set: archiving stops new use, it does not rewrite a map. The frozen rows are never edited or deleted on their own. The snapshot and pub/canonical_hash are NOT touched. Returns how many needs were frozen. Every input is passed explicitly by the caller.
function "req/freeze_needs" {
  input {
    int account_id filters=min:1
    int journey_map_id filters=min:1
    int journey_map_version_id filters=min:1
  }

  stack {
    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.journey_map_id == $input.journey_map_id
      return = {type: "list"}
    } as $needs

    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
      output = ["id", "key"]
    } as $stages

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
      return = {type: "list"}
      output = ["id", "key"]
    } as $lenses

    var $cell_ids {
      value = [-1]
    }

    foreach ($needs) {
      each as $n {
        array.push $cell_ids {
          value = $n.journey_cell_id
        }
      }
    }

    db.query journey_cell {
      where = $db.journey_cell.id in $cell_ids
      return = {type: "list"}
      output = ["id", "stage", "lens"]
    } as $cells

    var $stage_key {
      value = {}
    }

    var $lens_key {
      value = {}
    }

    var $cell_stage {
      value = {}
    }

    var $cell_lens {
      value = {}
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    foreach ($stages) {
      each as $s {
        var.update $t {
          value = $s.id|to_text
        }

        var.update $k {
          value = "s:" ~ $t
        }

        var.update $stage_key {
          value = $stage_key|set:$k:$s.key
        }
      }
    }

    foreach ($lenses) {
      each as $l {
        var.update $t {
          value = $l.id|to_text
        }

        var.update $k {
          value = "l:" ~ $t
        }

        var.update $lens_key {
          value = $lens_key|set:$k:$l.key
        }
      }
    }

    foreach ($cells) {
      each as $c {
        var.update $t {
          value = $c.id|to_text
        }

        var.update $k {
          value = "c:" ~ $t
        }

        var.update $cell_stage {
          value = $cell_stage|set:$k:$c.stage
        }

        var.update $cell_lens {
          value = $cell_lens|set:$k:$c.lens
        }
      }
    }

    // Pass 1: one row per need, with its two keys (empty when the step lost its stage or row).
    var $resolved {
      value = []
    }

    var $sid {
      value = 0
    }

    var $lid {
      value = 0
    }

    var $sk {
      value = ""
    }

    var $lk {
      value = ""
    }

    foreach ($needs) {
      each as $n {
        var.update $t {
          value = $n.journey_cell_id|to_text
        }

        var.update $k {
          value = "c:" ~ $t
        }

        var.update $sid {
          value = ($cell_stage|get:$k:null) ?? 0
        }

        var.update $lid {
          value = ($cell_lens|get:$k:null) ?? 0
        }

        var.update $t {
          value = $sid|to_text
        }

        var.update $k {
          value = "s:" ~ $t
        }

        var.update $sk {
          value = ($stage_key|get:$k:null) ?? ""
        }

        var.update $t {
          value = $lid|to_text
        }

        var.update $k {
          value = "l:" ~ $t
        }

        var.update $lk {
          value = ($lens_key|get:$k:null) ?? ""
        }

        array.push $resolved {
          value = {stage_key: $sk, lens_key: $lk, requirement_id: $n.requirement_id, strength: $n.strength}
        }
      }
    }

    // Pass 2: keep only the needs whose step still has both keys (a branch on the row's OWN fields).
    var $rows {
      value = []
    }

    foreach ($resolved) {
      each as $r {
        conditional {
          if ($r.stage_key != "" && $r.lens_key != "") {
            array.push $rows {
              value = $r
            }
          }
        }
      }
    }

    function.run "req/needs_hash" {
      input = {rows: $rows}
    } as $h

    foreach ($rows) {
      each as $w {
        db.add journey_map_version_requirement {
          data = {
            account_id            : $input.account_id
            journey_map_version_id: $input.journey_map_version_id
            stage_key             : $w.stage_key
            lens_key              : $w.lens_key
            requirement_id        : $w.requirement_id
            strength              : $w.strength
          }
        } as $_frozen
      }
    }

    var $frozen_n {
      value = $rows|count
    }

    // A version with no needs stores NO hash row (nothing to say, and its publish is unchanged).
    conditional {
      if ($frozen_n > 0) {
        db.add journey_map_version_needs_hash {
          data = {
            account_id            : $input.account_id
            journey_map_version_id: $input.journey_map_version_id
            need_count            : $frozen_n
            needs_hash            : $h.hash
          }
        } as $_hash_row
      }
    }
  }

  response = {frozen: $frozen_n, hash: (($frozen_n > 0) ? $h.hash : "")}
}
