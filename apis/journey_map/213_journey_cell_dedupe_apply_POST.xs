//  US-RES-1-02 — Apply dedupe on journey_cell (rev: defaults fix)
//  For every (journey_map, stage, lens) group with >1 row, pick a winner
//  and delete the rest. Designed to be safe to run repeatedly.
// 
//  Keep-rule (highest priority first):
//    1. status == "confirmed" beats anything not confirmed
//    2. is_locked == true     beats anything not locked
//    3. has content (non-empty)
//    4. most recent updated_at, then last_updated_at, then id (newest)
// 
//  If the top tier still has a tie (e.g. two confirmed rows with the same
//  updated_at), the group is SKIPPED, listed under ambiguous_groups, and
//  zero rows are deleted for it. No content is ever merged.
// 
//  Input:
//    journey_map_id? : limit scope to one map
//    dry_run         : default true — when true, NO writes happen
//    confirm         : must be true to actually delete (guard against fat-finger)
// 
//  Response shape:
//    { mode: "dry_run" | "applied",
//      groups_processed   : int,
//      rows_deleted       : int,       // 0 in dry_run
//      planned_deletions  : [ { group:{journey_map,stage,lens}, kept_id, removed_ids:[...], reason } ],
//      ambiguous_groups   : [ { group:{...}, candidate_ids:[...], reason } ],
//      ran_at             : timestamp }
query "journey_cell/dedupe_apply" verb=POST {
  api_group = "journey-map"

  input {
    int journey_map_id?
    bool dry_run?=true
    bool confirm?
  }

  stack {
    precondition ($input.dry_run || $input.confirm) {
      error_type = "badrequest"
      error = "Refusing to delete: pass dry_run=false AND confirm=true to actually delete rows."
    }
  
    // ── Load cells (optionally scoped) ──
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
  
    // ── Bucket cells by composite key journey_map:stage:lens ──
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
      
        var $existing {
          value = $cells_by_key|get:$ckey
        }
      
        conditional {
          if ($existing == null) {
            var $new_arr {
              value = []
            }
          
            array.push $new_arr {
              value = $c
            }
          
            var.update $cells_by_key {
              value = $cells_by_key|set:$ckey:$new_arr
            }
          
            var $meta_obj {
              value = {
                journey_map: $c.journey_map
                stage      : $c.stage
                lens       : $c.lens
              }
            }
          
            var.update $group_meta {
              value = $group_meta|set:$ckey:$meta_obj
            }
          }
        
          else {
            array.push $existing {
              value = $c
            }
          
            var.update $cells_by_key {
              value = $cells_by_key|set:$ckey:$existing
            }
          
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
  
    var $planned {
      value = []
    }
  
    var $ambiguous {
      value = []
    }
  
    var $deleted_count {
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
      
        // ── Tier 1: prefer confirmed ──
        var $confirmed_rows {
          value = []
        }
      
        foreach ($rows) {
          each as $r {
            conditional {
              if ($r.status == "confirmed") {
                array.push $confirmed_rows {
                  value = $r
                }
              }
            }
          }
        }
      
        var $candidates {
          value = $rows
        }
      
        var $tier {
          value = "most_recent"
        }
      
        conditional {
          if (($confirmed_rows|count) > 0) {
            var.update $candidates {
              value = $confirmed_rows
            }
          
            var.update $tier {
              value = "confirmed"
            }
          }
        }
      
        // ── Tier 2: prefer is_locked (only when no confirmed) ──
        conditional {
          if ($tier == "most_recent") {
            var $locked_rows {
              value = []
            }
          
            foreach ($rows) {
              each as $r {
                conditional {
                  if ($r.is_locked) {
                    array.push $locked_rows {
                      value = $r
                    }
                  }
                }
              }
            }
          
            conditional {
              if (($locked_rows|count) > 0) {
                var.update $candidates {
                  value = $locked_rows
                }
              
                var.update $tier {
                  value = "locked"
                }
              }
            }
          }
        }
      
        // ── Tier 3: prefer has-content ──
        conditional {
          if ($tier == "most_recent") {
            var $content_rows {
              value = []
            }
          
            foreach ($rows) {
              each as $r {
                conditional {
                  if ($r.content != null && $r.content != "") {
                    array.push $content_rows {
                      value = $r
                    }
                  }
                }
              }
            }
          
            conditional {
              if (($content_rows|count) > 0) {
                var.update $candidates {
                  value = $content_rows
                }
              
                var.update $tier {
                  value = "has_content"
                }
              }
            }
          }
        }
      
        // ── Tie-breaker: pick most-recent by updated_at, then id ──
        var $winner {
          value = null
        }
      
        foreach ($candidates) {
          each as $r {
            conditional {
              if ($winner == null) {
                var.update $winner {
                  value = $r
                }
              }
            
              elseif ($r.updated_at != null && $winner.updated_at != null && $r.updated_at > $winner.updated_at) {
                var.update $winner {
                  value = $r
                }
              }
            
              elseif (($r.updated_at == $winner.updated_at || ($r.updated_at == null && $winner.updated_at == null)) && $r.id > $winner.id) {
                var.update $winner {
                  value = $r
                }
              }
            }
          }
        }
      
        // ── Ambiguity check: when in a top tier (confirmed/locked) and >1 candidate
        //    shares the SAME updated_at as winner, skip the group ──
        var $top_tier_tied {
          value = false
        }
      
        conditional {
          if ($tier == "confirmed" || $tier == "locked") {
            var $same_ts {
              value = 0
            }
          
            foreach ($candidates) {
              each as $r {
                conditional {
                  if ($r.id != $winner.id && $r.updated_at == $winner.updated_at) {
                    var.update $same_ts {
                      value = ($same_ts + 1)
                    }
                  }
                }
              }
            }
          
            conditional {
              if ($same_ts > 0) {
                var.update $top_tier_tied {
                  value = true
                }
              }
            }
          }
        }
      
        conditional {
          if ($top_tier_tied) {
            var $cand_ids {
              value = []
            }
          
            foreach ($candidates) {
              each as $r {
                array.push $cand_ids {
                  value = $r.id
                }
              }
            }
          
            array.push $ambiguous {
              value = {
                group        : $meta
                candidate_ids: $cand_ids
                reason       : "Tie in tier '" ~ $tier ~ "' with identical updated_at - skipped to protect data."
              }
            }
          }
        
          else {
            // Build the loser list and (optionally) delete
            var $removed_ids {
              value = []
            }
          
            foreach ($rows) {
              each as $r {
                conditional {
                  if ($r.id != $winner.id) {
                    array.push $removed_ids {
                      value = $r.id
                    }
                  
                    conditional {
                      if ($input.dry_run == false) {
                        db.del journey_cell {
                          field_name = "id"
                          field_value = $r.id
                        }
                      
                        var.update $deleted_count {
                          value = ($deleted_count + 1)
                        }
                      }
                    }
                  }
                }
              }
            }
          
            array.push $planned {
              value = {
                group      : $meta
                kept_id    : $winner.id
                removed_ids: $removed_ids
                reason     : "Winner picked by tier '" ~ $tier ~ "'."
              }
            }
          }
        }
      }
    }
  
    var $mode_label {
      value = "applied"
    }
  
    conditional {
      if ($input.dry_run) {
        var.update $mode_label {
          value = "dry_run"
        }
      }
    }
  }

  response = {
    mode             : $mode_label
    groups_processed : $keys_with_dupes|count
    rows_deleted     : $deleted_count
    planned_deletions: $planned
    ambiguous_groups : $ambiguous
    ran_at           : "now"
  }
}