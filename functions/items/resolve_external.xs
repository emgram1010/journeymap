// SCALE-1 story 03 — THE one lookup from an outside system's products to catalog items, for the order webhook and any tool that receives outside product ids. For each product {external_id, name, quantity}: a linked product becomes {item_key, quantity}; a product marked "not an item" (a fee, a deposit) is counted and ignored; anything else is returned under unlinked and remembered in item_external_ref (the "Products to link" list) with its name and how often it has appeared. A link to an item that is switched off, or in another account, reads as unlinked. Names come from outside: trimmed and cut to 120 characters. Never throws for an unknown product.
function "items/resolve_external" {
  input {
    int account_id
    text source_system? filters=trim
    json products?
    bool remember?
  }

  stack {
    var $source {
      value = ($input.source_system ?? "")|trim|lower
    }

    var $products_text {
      value = ($input.products ?? [])|json_encode
    }

    var $products_first {
      value = $products_text|substr:0:1
    }

    var $products {
      value = []
    }

    conditional {
      if ($products_first == "[") {
        var.update $products {
          value = $input.products
        }
      }
    }

    db.query item_external_ref {
      where = $db.item_external_ref.account_id == $input.account_id && $db.item_external_ref.source_system == $source && $input.account_id != 0
      return = {type: "list"}
    } as $refs

    var $ref_ids {
      value = {}
    }

    var $ref_items {
      value = {}
    }

    var $ref_skip {
      value = {}
    }

    var $ref_seen {
      value = {}
    }

    var $k {
      value = ""
    }

    var $n {
      value = 0
    }

    foreach ($refs) {
      each as $r {
        var.update $k {
          value = "x:" ~ $r.external_id
        }

        var.update $ref_ids {
          value = $ref_ids|set:$k:$r.id
        }

        var.update $ref_items {
          value = $ref_items|set:$k:$r.item_type_id
        }

        var.update $n {
          value = $r.not_an_item|to_int
        }

        var.update $ref_skip {
          value = $ref_skip|set:$k:$n
        }

        var.update $ref_seen {
          value = $ref_seen|set:$k:$r.seen_count
        }
      }
    }

    db.query item_type {
      where = $db.item_type.account_id == $input.account_id && $db.item_type.is_active == true
      return = {type: "list"}
      output = ["id", "key"]
    } as $catalog

    var $keys {
      value = {}
    }

    foreach ($catalog) {
      each as $c {
        var.update $k {
          value = "i:" ~ ($c.id|to_text)
        }

        var.update $keys {
          value = $keys|set:$k:$c.key
        }
      }
    }

    // Pass 1: answer every question for each product, no branching.
    var $staged {
      value = []
    }

    var $ext {
      value = ""
    }

    var $name {
      value = ""
    }

    var $qty {
      value = 0
    }

    var $ref_id {
      value = 0
    }

    var $item_id {
      value = 0
    }

    var $skip {
      value = 0
    }

    var $seen {
      value = 0
    }

    var $ik {
      value = ""
    }

    var $item_key {
      value = ""
    }

    foreach ($products) {
      each as $p {
        var.update $ext {
          value = (($p.external_id ?? "")|to_text)|trim
        }

        var.update $name {
          value = ((($p.name ?? "")|to_text)|trim)|substr:0:120
        }

        var.update $qty {
          value = ($p.quantity ?? 0)|to_int
        }

        var.update $k {
          value = "x:" ~ $ext
        }

        var.update $ref_id {
          value = ($ref_ids|get:$k:null) ?? 0
        }

        var.update $item_id {
          value = ($ref_items|get:$k:null) ?? 0
        }

        var.update $skip {
          value = ($ref_skip|get:$k:null) ?? 0
        }

        var.update $seen {
          value = ($ref_seen|get:$k:null) ?? 0
        }

        var.update $ik {
          value = "i:" ~ ($item_id|to_text)
        }

        var.update $item_key {
          value = ($keys|get:$ik:null) ?? ""
        }

        array.push $staged {
          value = {external_id: $ext, name: $name, quantity: $qty, ref_id: $ref_id, skip: $skip, seen: $seen, item_key: $item_key, has_id: ($ext != "")}
        }
      }
    }

    var $items {
      value = []
    }

    var $unlinked {
      value = []
    }

    var $ignored {
      value = 0
    }

    foreach ($staged) {
      each as $s {
        conditional {
          if ($s.has_id == false) {
            array.push $unlinked {
              value = {external_id: "", name: $s.name, quantity: $s.quantity}
            }
          }

          elseif ($s.skip == 1) {
            math.add $ignored {
              value = 1
            }
          }

          elseif ($s.item_key != "") {
            array.push $items {
              value = {item_key: $s.item_key, quantity: $s.quantity, external_id: $s.external_id}
            }
          }

          else {
            array.push $unlinked {
              value = {external_id: $s.external_id, name: $s.name, quantity: $s.quantity}
            }
          }
        }
      }
    }

    // Remember what was seen, so "Products to link" shows the name and how often it appeared.
    conditional {
      if ($input.remember == true) {
        foreach ($staged) {
          each as $w {
            conditional {
              if ($w.has_id == true && $w.ref_id == 0) {
                try_catch {
                  try {
                    db.add item_external_ref {
                      data = {created_at: "now", updated_at: "now", account_id: $input.account_id, source_system: $source, external_id: $w.external_id, external_name: $w.name, item_type_id: 0, not_an_item: false, seen_count: 1, last_seen_at: "now", updated_by_user_id: 0}
                    } as $new_ref
                  }

                  catch {
                    var $race {
                      value = true
                    }
                  }
                }
              }

              elseif ($w.has_id == true) {
                db.patch item_external_ref {
                  field_name = "id"
                  field_value = $w.ref_id
                  data = {seen_count: ($w.seen + 1), last_seen_at: "now", external_name: $w.name}
                } as $seen_ref
              }
            }
          }
        }
      }
    }
  }

  response = {source_system: $source, items: $items, unlinked: $unlinked, ignored: $ignored}
}
