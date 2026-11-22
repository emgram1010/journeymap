// SAFE-1 (US-SAFE-1-01 counter-measure) — REPORT ONLY. Lists cells the old update_cell bug may
// have wiped: an AI-written cell with no text but a non-zero time (a times-only call blanked the
// text). Changes nothing. Shown to the founder; nothing is restored automatically.
function "ops/suspect_wiped_cells" {
  input {
  }

  stack {
    db.query journey_cell {
      where = $db.journey_cell.change_source == "ai" && ($db.journey_cell.content == "" || $db.journey_cell.content == null) && $db.journey_cell.time_duration_value != 0
      return = {type: "list"}
      output = ["id", "journey_map", "updated_at", "time_duration_value", "time_duration_unit"]
    } as $rows

    var $count {
      value = $rows|count
    }
  }

  response = {count: $count, cells: $rows}
}
