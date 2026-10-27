// ITEM-1 (US-ITEM-1-03) — Validates the FULL body of an Items cell write:
// {scales_with, lines: [{item_key, method_key, minutes_per_unit}]}. The
// caller (the PATCH endpoint) always sends the whole cell; the server
// always replaces (two-step JSON patch, CLAUDE.md).
//
// Returns ok=true with normalized_lines when everything passes.
// dropped_lines_warn is set (not a rejection) when per_order was sent
// with non-empty lines -- the server empties it and the caller logs a
// warn event (US-ITEM-1-03's own rule, not an input error).
//
// $seen_pairs is built with |get on a VARIABLE key and tested for null,
// never trusted with a literal default (CLAUDE.md: a variable key's
// default is silently discarded; null-if-absent is the one behaviour to
// rely on). "::" joins the pair, never "|" (CLAUDE.md: a pipe inside a
// string literal breaks the parser).
function "items/validate_items_cell" {
  input {
    int account_id filters=min:1
    int journey_lens_id filters=min:1
    text scales_with? filters=trim|lower
    json lines?
  }

  stack {
    var $scales_with_ok {
      value = ($input.scales_with == "per_order" || $input.scales_with == "per_unit" || $input.scales_with == "per_flagged_unit")
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($scales_with_ok == false) {
        var.update $reject_code {
          value = "E-ITM-003"
        }

        var.update $reject_msg {
          value = "Choose per order, per unit or per flagged unit. (E-ITM-003)"
        }
      }
    }

    var $dropped_lines_warn {
      value = false
    }

    var $normalized_lines {
      value = []
    }

    // ── per_order: lines must be empty. Not an input error -- the
    // server empties it and the caller logs a warn (US-ITEM-1-03). ──
    conditional {
      if ($reject_code == "" && $input.scales_with == "per_order") {
        conditional {
          if (($input.lines|count) > 0) {
            var.update $dropped_lines_warn {
              value = true
            }
          }
        }
      }
    }

    // ── per_unit / per_flagged_unit: validate every line. ──
    conditional {
      if ($reject_code == "" && $input.scales_with != "per_order") {
        db.query journey_lens_item {
          where = $db.journey_lens_item.journey_lens == $input.journey_lens_id
          return = {type: "list"}
        } as $chosen_items

        var $allowed_item_type_ids {
          value = {}
        }

        foreach ($chosen_items) {
          each as $ci {
            var $ci_key {
              value = $ci.item_type_id|to_text
            }

            var.update $allowed_item_type_ids {
              value = $allowed_item_type_ids|set:$ci_key:true
            }
          }
        }

        var $seen_pairs {
          value = {}
        }

        foreach ($input.lines) {
          each as $line {
            // Keep checking subsequent lines even after the first bad one,
            // but never let a later check overwrite the first failure --
            // $reject_code is only ever set once per cell, read fresh each
            // iteration (the loop item's own field, plus a value set
            // before the loop started), never a trap shape.
            conditional {
              if ($reject_code == "") {
                db.query item_type {
                  where = $db.item_type.account_id == $input.account_id && $db.item_type.key == $line.item_key
                  return = {type: "single"}
                } as $matched_item

                var $item_ok {
                  value = false
                }

                conditional {
                  if ($matched_item != null && $matched_item.is_active == true) {
                    var $matched_item_key {
                      value = $matched_item.id|to_text
                    }

                    var $item_allowed {
                      value = $allowed_item_type_ids|get:$matched_item_key
                    }

                    var.update $item_ok {
                      value = ($item_allowed != null)
                    }
                  }
                }

                conditional {
                  if ($item_ok == false) {
                    var.update $reject_code {
                      value = "E-ITM-002"
                    }

                    var.update $reject_msg {
                      value = "Add that item to this map's item list first. (E-ITM-002)"
                    }
                  }
                }

                conditional {
                  if ($reject_code == "") {
                    db.query method {
                      where = $db.method.account_id == $input.account_id && $db.method.key == $line.method_key
                      return = {type: "single"}
                    } as $matched_method

                    conditional {
                      if ($matched_method == null || $matched_method.is_active == false) {
                        var.update $reject_code {
                          value = "E-ITM-005"
                        }

                        var.update $reject_msg {
                          value = "Pick a method from your catalog. (E-ITM-005)"
                        }
                      }
                    }
                  }
                }

                conditional {
                  if ($reject_code == "" && ($line|has:"minutes_per_unit") && $line.minutes_per_unit != null) {
                    var $minutes_ok {
                      value = ($line.minutes_per_unit >= 0 && $line.minutes_per_unit <= 1440)
                    }

                    // 2-decimal check, without a |round filter (unconfirmed
                    // in this workspace): manual round-half-up via |to_int
                    // (confirmed), then an epsilon compare against the
                    // original so float multiplication noise (e.g.
                    // 2.1*100 landing a hair off 210) never false-rejects
                    // a legitimate 2-decimal value.
                    var $scaled {
                      value = $line.minutes_per_unit * 100
                    }

                    var $scaled_rounded {
                      value = ($scaled + 0.5)|to_int
                    }

                    var $rounding_diff {
                      value = $scaled - $scaled_rounded
                    }

                    var $rounding_ok {
                      value = ($rounding_diff > -0.01 && $rounding_diff < 0.01)
                    }

                    conditional {
                      if ($minutes_ok == false || $rounding_ok == false) {
                        var.update $reject_code {
                          value = "E-ITM-004"
                        }

                        var.update $reject_msg {
                          value = "Enter minutes for one item, like 2.5, or leave it empty for now. (E-ITM-004)"
                        }
                      }
                    }
                  }
                }

                conditional {
                  if ($reject_code == "") {
                    var $pair_key {
                      value = $line.item_key ~ "::" ~ $line.method_key
                    }

                    var $existing_pair {
                      value = $seen_pairs|get:$pair_key
                    }

                    conditional {
                      if ($existing_pair != null) {
                        var.update $reject_code {
                          value = "E-ITM-006"
                        }

                        var.update $reject_msg {
                          value = "That item already has a line for that method here. (E-ITM-006)"
                        }
                      }

                      else {
                        var.update $seen_pairs {
                          value = $seen_pairs|set:$pair_key:true
                        }

                        array.push $normalized_lines {
                          value = {
                            item_key         : $line.item_key
                            method_key       : $line.method_key
                            minutes_per_unit : (($line|has:"minutes_per_unit") ? $line.minutes_per_unit : null)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    ok               : ($reject_code == "")
    code             : $reject_code
    message          : $reject_msg
    normalized_lines : $normalized_lines
    dropped_lines_warn: $dropped_lines_warn
  }
}
