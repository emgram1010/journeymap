//  US-RES-1-01 — Dedupe scan for journey_cell (READ-ONLY)
//  Identifies rows that violate the intended uniqueness on
//  (journey_map, stage, lens). Produces a remediation report for US-RES-1-02
//  to consume. No writes — idempotent and safe to run anytime.
// 
//  Optional input: journey_map_id scopes the scan to a single map.
//  When omitted, scans every row in journey_cell.
// 
//  Response shape:
//  {
//    duplicate_groups_found: int,
//    total_duplicate_rows  : int,   // sum of rows across all duplicate groups
//    total_cells_scanned   : int,
//    groups: [
//      {
//        journey_map: int, stage: int, lens: int,
//        row_count  : int,
//        rows: [
//          { id, status, is_locked, change_source,
//            updated_at, last_updated_at, has_content }
//        ]
//      }
//    ],
//    scanned_at: timestamp
//  }
query "journey_cell/dedupe_scan" verb=POST {
  api_group = "journey-map"

  input {
    // Optional: limit the scan to a single journey map.
    // When null/omitted, scans every row in journey_cell.
    int journey_map_id?
  }

  stack {
    // ── Load cells to scan (optionally scoped to one map) ──
    conditional {
      if ($input.journey_map_id != null) {
        db.query journey_cell {
          where = $db.journey_cell.journey_map == $input.journey_map_id
          sort = {id: "asc"}
          return = {type: "list"}
        } as $raw_cells
      }
    
      else {
        db.query journey_cell {
          sort = {id: "asc"}
          return = {type: "list"}
        } as $raw_cells
      }
    }
  
    // ── Group cells by composite key "journey_map|stage|lens" ──
    var $cells_by_key {
      value = {}
    }
  
    var $group_meta {
      value = {}
    }
  
    var $keys_with_dupes {
      value = []
    }
  
    foreach ($raw_cells) {
      each as $c {
        var $ckey {
          value = ($c.journey_map|to_text) ~ ":" ~ ($c.stage|to_text) ~ ":" ~ ($c.lens|to_text)
        }
      
        var $row_summary {
          value = {
            id             : $c.id
            status         : $c.status
            is_locked      : $c.is_locked
            change_source  : $c.change_source
            updated_at     : $c.updated_at
            last_updated_at: $c.last_updated_at
            has_content    : $c.content != null && $c.content != ""
          }
        }
      
        var $existing {
          value = $cells_by_key|get:$ckey
        }
      
        conditional {
          if ($existing == null) {
            // First sighting of this ckey — init group + record meta
            var $new_arr {
              value = []
            }
          
            array.push $new_arr {
              value = $row_summary
            }
          
            var.update $cells_by_key {
              value = $cells_by_key|set:$ckey:$new_arr
            }
          
            var.update $group_meta {
              value = $group_meta
                |set:$ckey:{journey_map: $c.journey_map, stage: $c.stage, lens: $c.lens}
            }
          }
        
          else {
            // Already seen — append to the group's row list
            array.push $existing {
              value = $row_summary
            }
          
            var.update $cells_by_key {
              value = $cells_by_key|set:$ckey:$existing
            }
          
            // First time this key qualifies as a duplicate (count went 1 → 2)
            conditional {
              if (($existing|count) == 2) {
                array.push $keys_with_dupes {
                  value = $ckey
                }
              }
            }
          }
        }
      }
    }
  
    // ── Build the output groups array from the duplicate-key list ──
    var $output_groups {
      value = []
    }
  
    var $total_dup_rows {
      value = 0
    }
  
    foreach ($keys_with_dupes) {
      each as $ckey {
        var $rows {
          value = $cells_by_key|get:$ckey
        }
      
        var $meta {
          value = $group_meta|get:$ckey
        }
      
        array.push $output_groups {
          value = {
            journey_map: $meta.journey_map
            stage      : $meta.stage
            lens       : $meta.lens
            row_count  : $rows|count
            rows       : $rows
          }
        }
      
        var.update $total_dup_rows {
          value = $total_dup_rows + ($rows|count)
        }
      }
    }
  
    var $total_scanned {
      value = $raw_cells|count
    }
  }

  response = {
    duplicate_groups_found: $output_groups|count
    total_duplicate_rows  : $total_dup_rows
    total_cells_scanned   : $total_scanned
    groups                : $output_groups
    scanned_at            : "now"
  }
}