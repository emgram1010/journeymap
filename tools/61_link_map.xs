// LM-1: MCP tool — create a directed cell→map link within a Journey Architecture.
// Delegates to the journey_link table. Validates architecture, map membership, and cell ownership.
// Uniqueness enforced: (source_cell, target_map) must not already exist.
tool link_map {
  instructions = "Create a directed link from a specific cell in one map to another map within the same Journey Architecture. Call get_map first to find the source_cell_id — match by stage_key + lens_key in the cells array. link_type: exception = something went wrong here and the target map handles recovery; anti_journey = actor did NOT follow expected path and target map handles the alternate; sub_journey = target map is a delegated sub-process invoked at this cell. Both maps must belong to the same architecture. One cell can only link to a given target map once — re-submitting the same pair returns an error. After link_map, call publish_map on the source map to include the link in the automation snapshot."

  input {
    int  journey_architecture_id filters=min:1
    int  source_map_id           filters=min:1
    int  source_cell_id          filters=min:1
    int  target_map_id           filters=min:1
    enum link_type {
      values = ["exception", "anti_journey", "sub_journey"]
    }
    text label? filters=trim
  }

  stack {
    precondition ($input.source_map_id != $input.target_map_id) {
      error_type = "inputerror"
      error = "source_map_id and target_map_id must be different maps"
    }

    // 1 — Verify architecture
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $architecture

    precondition ($architecture != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }

    // 2 — Verify source map belongs to architecture
    db.get journey_map {
      field_name = "id"
      field_value = $input.source_map_id
    } as $source_map

    precondition ($source_map != null) {
      error_type = "notfound"
      error = "Source map not found"
    }

    precondition ($source_map.journey_architecture == $input.journey_architecture_id) {
      error_type = "inputerror"
      error = "Source map does not belong to this architecture"
    }

    // 3 — Verify target map belongs to architecture
    db.get journey_map {
      field_name = "id"
      field_value = $input.target_map_id
    } as $target_map

    precondition ($target_map != null) {
      error_type = "notfound"
      error = "Target map not found"
    }

    precondition ($target_map.journey_architecture == $input.journey_architecture_id) {
      error_type = "inputerror"
      error = "Target map does not belong to this architecture"
    }

    // 4 — Verify source cell belongs to source map
    db.get journey_cell {
      field_name = "id"
      field_value = $input.source_cell_id
    } as $source_cell

    precondition ($source_cell != null) {
      error_type = "notfound"
      error = "Source cell not found"
    }

    precondition ($source_cell.journey_map == $input.source_map_id) {
      error_type = "inputerror"
      error = "Source cell does not belong to the source map"
    }

    // 5 — Enforce uniqueness: (source_cell, target_map)
    db.query journey_link {
      where = ($db.journey_link.source_cell == $input.source_cell_id) && ($db.journey_link.target_map == $input.target_map_id)
      return = {type: "list"}
    } as $existing_links

    var $existing_link_count {
      value = $existing_links|count
    }

    precondition ($existing_link_count == 0) {
      error_type = "inputerror"
      error = "A link from this cell to this target map already exists. Delete the existing link via API before creating a new one."
    }

    // 6 — Create the link (owner_user inherited from architecture)
    db.add journey_link {
      data = {
        created_at          : "now"
        updated_at          : "now"
        journey_architecture: $input.journey_architecture_id
        source_map          : $input.source_map_id
        source_cell         : $input.source_cell_id
        target_map          : $input.target_map_id
        link_type           : $input.link_type
        label               : $input.label
        owner_user          : $architecture.owner_user
      }
    } as $link
  }

  response = {
    id                  : $link.id
    journey_architecture: $link.journey_architecture
    source_map          : $link.source_map
    source_cell         : $link.source_cell
    target_map          : $link.target_map
    link_type           : $link.link_type
    label               : $link.label
    created_at          : $link.created_at
  }
  guid = "SsBt8Wm7t0O6-9WMPaGZTw5yVC0"
}
