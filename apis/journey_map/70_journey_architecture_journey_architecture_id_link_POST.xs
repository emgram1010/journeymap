// Create a directed link from a specific cell in one map to another map.
// Both maps must belong to the same architecture as the authenticated owner.
// Uniqueness enforced: (source_cell_id, target_map_id) must not already exist.
// owner_user is inherited from the architecture — never accepted from client input.
query "journey_architecture/{journey_architecture_id}/link" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
  
    // The map where the breakpoint originates.
    int source_map_id? filters=min:1
  
    // The specific cell anchor — required for cell-level precision.
    int source_cell_id? filters=min:1
  
    // The map being linked to.
    int target_map_id? filters=min:1
  
    // Type of relationship.
    enum link_type? {
      values = ["exception", "anti_journey", "sub_journey"]
    }
  
    // Optional label for the graph edge.
    text label? filters=trim
  }

  stack {
    // Validate required fields
    precondition ($input.source_map_id != null) {
      error_type = "inputerror"
      error = "source_map_id is required"
    }
  
    precondition ($input.source_cell_id != null) {
      error_type = "inputerror"
      error = "source_cell_id is required — links must start from a specific cell"
    }
  
    precondition ($input.target_map_id != null) {
      error_type = "inputerror"
      error = "target_map_id is required"
    }
  
    precondition ($input.link_type != null) {
      error_type = "inputerror"
      error = "link_type is required"
    }
  
    // No self-links
    precondition ($input.source_map_id != $input.target_map_id) {
      error_type = "inputerror"
      error = "source_map_id and target_map_id must be different maps"
    }
  
    // Fetch architecture; verify ownership
    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $architecture
  
    precondition ($architecture != null) {
      error_type = "notfound"
      error = "Journey Architecture not found"
    }
  
    precondition ($architecture.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    // Verify source map belongs to this architecture
    db.get journey_map {
      field_name = "id"
      field_value = $input.source_map_id
    } as $source_map
  
    precondition ($source_map != null && $source_map.journey_architecture == $input.journey_architecture_id) {
      error_type = "inputerror"
      error = "source_map does not belong to this architecture"
    }
  
    // Verify target map belongs to this architecture
    db.get journey_map {
      field_name = "id"
      field_value = $input.target_map_id
    } as $target_map
  
    precondition ($target_map != null && $target_map.journey_architecture == $input.journey_architecture_id) {
      error_type = "inputerror"
      error = "target_map does not belong to this architecture"
    }
  
    // Verify source cell belongs to source map
    db.get journey_cell {
      field_name = "id"
      field_value = $input.source_cell_id
    } as $source_cell
  
    precondition ($source_cell != null && $source_cell.journey_map == $input.source_map_id) {
      error_type = "inputerror"
      error = "source_cell does not belong to source_map"
    }
  
    // Enforce uniqueness: check for existing link with same (source_cell, target_map)
    db.query journey_link {
      where = $db.journey_link.source_cell == $input.source_cell_id && $db.journey_link.target_map == $input.target_map_id
      return = {type: "exists"}
    } as $link_exists
  
    precondition ($link_exists == false) {
      error_type = "inputerror"
      error = "A link from this cell to that map already exists. Edit the existing link instead."
    }
  
    // Create the link — owner_user inherited from architecture
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

  response = $link
}