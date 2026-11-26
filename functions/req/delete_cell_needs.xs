// REQ-1 story 04 — a step's needs go with the step. WRITE-ONLY helper called wherever a journey_cell is deleted (a single cell, a removed row or stage, a deleted map) so no need is ever left pointing at a cell that is gone. Reads the cell's needs first, then deletes each by its OWN id (a delete by a shared field removes only the first match). Safe inside the caller's transaction. Returns how many were removed. Frozen needs on PUBLISHED versions are never touched here: they belong to the version, not the cell.
function "req/delete_cell_needs" {
  input {
    int journey_cell_id filters=min:1
  }

  stack {
    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.journey_cell_id == $input.journey_cell_id
      return = {type: "list"}
      output = ["id"]
    } as $rows

    foreach ($rows) {
      each as $r {
        db.del journey_cell_requirement {
          field_name = "id"
          field_value = $r.id
        }
      }
    }
  }

  response = {removed: ($rows|count)}
}
