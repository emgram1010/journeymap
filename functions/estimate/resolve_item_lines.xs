// SCALE-1 story 01 — turn a list of {item_key, quantity} into order lines for a job on one map, for the tools and the order webhook (a person uses the lines screen, endpoint 607). READ-ONLY and never throws: the caller refuses when ok is false, before anything is written. Rules: quantity is a whole number 1 to 9999 (the same range as E-EST-001); the same key twice is added into one line; a key that is not an active catalog item is returned under unknown_items and gets no line; a catalog item the map's latest version has no time for still gets a line and is also returned under not_on_map (the estimate then reports it as missing and adds 0, never a default). Branches only read the loop item (rows are staged first).
function "estimate/resolve_item_lines" {
  input {
    int account_id
    int journey_map_id
    json items?
  }

  stack {
    var $items_text {
      value = ($input.items ?? [])|json_encode
    }

    var $items_first {
      value = $items_text|substr:0:1
    }

    var $items {
      value = []
    }

    conditional {
      if ($items_first == "[") {
        var.update $items {
          value = $input.items
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $input.journey_map_id
      sort = {journey_map_version.version_no: "desc"}
      return = {type: "list"}
      output = ["id", "version_no"]
    } as $versions

    var $version {
      value = $versions|first
    }

    var $version_id {
      value = $version|get:"id":0
    }

    db.query stage_rate {
      where = $db.stage_rate.journey_map_version_id == $version_id && $version_id != 0
      return = {type: "list"}
      output = ["id", "quantity_key"]
    } as $rates

    var $on_map {
      value = {}
    }

    var $k {
      value = ""
    }

    var $next {
      value = 0
    }

    foreach ($rates) {
      each as $r {
        var.update $k {
          value = "k:" ~ $r.quantity_key
        }

        var.update $on_map {
          value = $on_map|set:$k:1
        }
      }
    }

    db.query item_type {
      where = $db.item_type.account_id == $input.account_id && $input.account_id != 0
      return = {type: "list"}
      output = ["id", "key", "is_active"]
    } as $catalog

    var $item_ids {
      value = {}
    }

    foreach ($catalog) {
      each as $c {
        var.update $k {
          value = "k:" ~ $c.key
        }

        // Only active items count: a switched-off item reads as unknown.
        var.update $next {
          value = $c.id * ($c.is_active|to_int)
        }

        var.update $item_ids {
          value = $item_ids|set:$k:$next
        }
      }
    }

    // Pass 1: stage every row with its checks already answered.
    var $staged {
      value = []
    }

    var $sums {
      value = {}
    }

    var $key {
      value = ""
    }

    var $qty {
      value = 0
    }

    var $qty_int {
      value = 0
    }

    var $valid {
      value = false
    }

    var $prev {
      value = 0
    }

    foreach ($items) {
      each as $it {
        var.update $key {
          value = (($it.item_key ?? "")|to_text)|trim|lower
        }

        var.update $qty {
          value = $it.quantity ?? 0
        }

        var.update $qty_int {
          value = $qty|to_int
        }

        var.update $valid {
          value = ($key != "" && $qty == $qty_int && $qty_int >= 1 && $qty_int <= 9999)
        }

        var.update $k {
          value = "k:" ~ $key
        }

        var.update $prev {
          value = ($sums|get:$k:null) ?? 0
        }

        var.update $next {
          value = $prev + ($qty_int * ($valid|to_int))
        }

        var.update $sums {
          value = $sums|set:$k:$next
        }

        array.push $staged {
          value = {key: $key, valid: $valid, first: ($prev == 0)}
        }
      }
    }

    // Pass 2: bad rows by name, and each key once in the order it first appeared.
    var $bad {
      value = []
    }

    var $unique {
      value = []
    }

    foreach ($staged) {
      each as $s {
        conditional {
          if ($s.valid == false) {
            array.push $bad {
              value = $s.key
            }
          }

          elseif ($s.first == true) {
            array.push $unique {
              value = $s.key
            }
          }
        }
      }
    }

    // Pass 3: classify each key.
    var $classified {
      value = []
    }

    var $item_id {
      value = 0
    }

    var $has_rate {
      value = 0
    }

    var $total {
      value = 0
    }

    foreach ($unique) {
      each as $u {
        var.update $k {
          value = "k:" ~ $u
        }

        var.update $item_id {
          value = ($item_ids|get:$k:null) ?? 0
        }

        var.update $has_rate {
          value = ($on_map|get:$k:null) ?? 0
        }

        var.update $total {
          value = ($sums|get:$k:null) ?? 0
        }

        array.push $classified {
          value = {item_key: $u, quantity: $total, item_type_id: $item_id, has_rate: $has_rate, over: ($total > 9999)}
        }
      }
    }

    var $lines {
      value = []
    }

    var $unknown {
      value = []
    }

    var $not_on_map {
      value = []
    }

    foreach ($classified) {
      each as $c2 {
        conditional {
          if ($c2.over == true) {
            array.push $bad {
              value = $c2.item_key
            }
          }

          elseif ($c2.item_type_id == 0) {
            array.push $unknown {
              value = {item_key: $c2.item_key, quantity: $c2.quantity}
            }
          }

          else {
            array.push $lines {
              value = {item_type_id: $c2.item_type_id, quantity: $c2.quantity, item_key: $c2.item_key}
            }

            conditional {
              if ($c2.has_rate == 0) {
                array.push $not_on_map {
                  value = {item_key: $c2.item_key, quantity: $c2.quantity}
                }
              }
            }
          }
        }
      }
    }

    var $ok {
      value = ($bad|count) == 0
    }

    var $message {
      value = ""
    }

    conditional {
      if ($ok == false) {
        var.update $message {
          value = "Each item needs an item_key and a whole quantity from 1 to 9999. Check: " ~ ($bad|join:", ") ~ ". Nothing was added. (E-EST-001)"
        }
      }
    }
  }

  response = {ok: $ok, message: $message, journey_map_version_id: $version_id, item_count: ($items|count), lines: $lines, unknown_items: $unknown, not_on_map: $not_on_map}
}
