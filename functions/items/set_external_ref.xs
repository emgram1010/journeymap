// SCALE-1 story 03 — link one outside product to a catalog item, mark it "not an item", or clear it. The product is named by its row id, or by source_system + external_id (a new row is made when it has never been seen). The item must be in the caller's account (E-SCL-002). A product that is already linked to a different item is not changed until move is true: status "move_needed" comes back naming the current item. One product has one row (unique index), so a second save at the same moment updates the same row. Every change is logged with the item before and after.
function "items/set_external_ref" {
  input {
    int account_id
    int user_id
    int ref_id?
    text source_system? filters=trim
    text external_id? filters=trim
    text external_name? filters=trim
    int item_type_id?
    bool not_an_item?
    bool move?
  }

  stack {
    var $source {
      value = ($input.source_system ?? "")|trim|lower
    }

    var $ext {
      value = ($input.external_id ?? "")|trim
    }

    var $name {
      value = (($input.external_name ?? "")|trim)|substr:0:120
    }

    precondition ($input.account_id != 0 && ($input.ref_id != 0 || ($source != "" && $ext != "" && ($source|strlen) <= 40 && ($ext|strlen) <= 120))) {
      error_type = "inputerror"
      error = "Say which product: its source system (up to 40 characters) and its id (up to 120). (E-SCL-001)"
    }

    db.query item_external_ref {
      where = $db.item_external_ref.account_id == $input.account_id && (($input.ref_id != 0 && $db.item_external_ref.id == $input.ref_id) || ($input.ref_id == 0 && $db.item_external_ref.source_system == $source && $db.item_external_ref.external_id == $ext))
      return = {type: "single"}
    } as $ref

    var $ref_id {
      value = $ref|get:"id":0
    }

    precondition ($ref_id != 0 || $input.ref_id == 0) {
      error_type = "notfound"
      error = "Product not found. (E-SCL-004)"
    }

    var $new_item {
      value = $input.item_type_id ?? 0
    }

    var $skip {
      value = $input.not_an_item == true
    }

    conditional {
      if ($skip) {
        var.update $new_item {
          value = 0
        }
      }
    }

    db.query item_type {
      where = $db.item_type.id == $new_item && $db.item_type.account_id == $input.account_id && $new_item != 0
      return = {type: "single"}
      output = ["id", "key", "label"]
    } as $item

    var $item_id {
      value = $item|get:"id":0
    }

    precondition ($new_item == 0 || $item_id != 0) {
      error_type = "notfound"
      error = "That item isn't in your catalog. (E-SCL-002)"
    }

    var $old_item {
      value = $ref|get:"item_type_id":0
    }

    var $status {
      value = "saved"
    }

    conditional {
      if ($ref_id != 0 && $old_item != 0 && $new_item != 0 && $old_item != $new_item && $input.move != true) {
        var.update $status {
          value = "move_needed"
        }
      }

      elseif ($ref_id == 0) {
        try_catch {
          try {
            db.add item_external_ref {
              data = {created_at: "now", updated_at: "now", account_id: $input.account_id, source_system: $source, external_id: $ext, external_name: $name, item_type_id: $new_item, not_an_item: $skip, seen_count: 0, updated_by_user_id: $input.user_id}
            } as $made

            var.update $ref_id {
              value = $made.id
            }
          }

          catch {
            var.update $status {
              value = "retry"
            }
          }
        }
      }

      else {
        db.patch item_external_ref {
          field_name = "id"
          field_value = $ref_id
          data = {item_type_id: $new_item, not_an_item: $skip, updated_at: "now", updated_by_user_id: $input.user_id}
        } as $patched
      }
    }

    precondition ($status != "retry") {
      error_type = "standard"
      error = "Someone else just saved this product. Reload and try again. (E-SCL-003)"
    }

    conditional {
      if ($status == "saved") {
        function.run "ops/log_event" {
          input = {feature: "SCALE-1", step: "product_link_set", outcome: "success", severity: "info", error_code: "", message: "An outside product's link to a catalog item was changed.", user_id: $input.user_id, account_id: $input.account_id, entity_type: "item_external_ref", entity_id: $ref_id, correlation_id: "", duration_ms: 0, metadata: {item_before: $old_item, item_after: $new_item, not_an_item: $skip}}
        } as $_ev
      }
    }
  }

  response = {status: $status, ref_id: $ref_id, item_type_id: $new_item, not_an_item: $skip, current_item_type_id: $old_item}
}
