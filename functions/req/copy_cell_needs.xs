// REQ-1 story 04 — a cloned map keeps its needs. WRITE-ONLY helper called by the scenario clone right after it makes the copy of a cell: every need on the source cell is added to the new cell, same requirement, same hard/soft. Reads the source's needs first and writes each by its own row. Safe inside the caller's transaction. Returns how many were copied. The requirement list is per account and a clone stays in its account, so the same requirement ids are right.
function "req/copy_cell_needs" {
  input {
    int from_cell_id filters=min:1
    int to_cell_id filters=min:1
    int to_map_id filters=min:1
    int user_id?
  }

  stack {
    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.journey_cell_id == $input.from_cell_id
      return = {type: "list"}
    } as $rows

    foreach ($rows) {
      each as $r {
        db.add journey_cell_requirement {
          data = {
            account_id     : $r.account_id
            journey_map_id : $input.to_map_id
            journey_cell_id: $input.to_cell_id
            requirement_id : $r.requirement_id
            strength       : $r.strength
            updated_by     : $input.user_id
            updated_at     : "now"
          }
        } as $_copied
      }
    }
  }

  response = {copied: ($rows|count)}
}
