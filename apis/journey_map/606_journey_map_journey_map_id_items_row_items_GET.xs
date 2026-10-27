// ITEM-1 (US-ITEM-1-02/04) — Read the map's CURRENT chosen-item set,
// joined with item_type for display (key, label, unit,
// default_method_id) -- the PUT endpoint's own response only carries
// {item_type_id, sort_order}, not enough for the picker or the cell
// editor to render anything. The account's FULL catalog (for "which
// items/methods exist to choose from") is read separately, from
// CAT-1's own GET /item-type and GET /method -- this endpoint is only
// the per-map subset.
query "journey_map/{journey_map_id}/items-row/items" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id && $db.journey_lens.template_key == "items-v1"
      return = {type: "single"}
    } as $items_lens

    var $rows {
      value = []
    }

    conditional {
      if ($items_lens != null) {
        db.query journey_lens_item {
          where = $db.journey_lens_item.journey_lens == $items_lens.id
          sort = {sort_order: "asc"}
          return = {type: "list"}
        } as $lens_items

        foreach ($lens_items) {
          each as $li {
            db.get item_type {
              field_name = "id"
              field_value = $li.item_type_id
            } as $item

            conditional {
              if ($item != null) {
                array.push $rows {
                  value = {
                    item_type_id      : $item.id
                    key               : $item.key
                    label             : $item.label
                    unit              : $item.unit
                    default_method_id: $item.default_method_id
                    is_active         : $item.is_active
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
    items_lens_id: ($items_lens != null ? $items_lens.id : null)
    items        : $rows
  }
}
