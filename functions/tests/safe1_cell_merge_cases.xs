// SAFE-1 tests T-SAFE-01-1..6 and T-SAFE-02-1 — golden cases for journey/cell_merge_patch.
// Pure: reads nothing, writes nothing. Run with runWorkspaceFunction; all_pass must be true.
// Every comparison coalesces first, because == is loose ("" == null and 0 == null are true).
function "tests/safe1_cell_merge_cases" {
  input {
  }

  stack {
    var $cell {
      value = {content: "Load the truck", actor_fields: {task_objective: "x"}, time_duration_value: 20, time_duration_unit: "minutes", planned_duration: 20, actual_duration: 25}
    }

    // c1 — times-only keeps the text (T-SAFE-01-1)
    function.run "journey/cell_merge_patch" {
      input = {cell: $cell, patch: {time_duration_value: 30, time_duration_unit: "hours"}}
    } as $r1

    var $c1 {
      value = ((($r1.data.content ?? "__null__") == "Load the truck") && (($r1.data.time_duration_value ?? -1) == 30) && (($r1.data.time_duration_unit ?? "__null__") == "hours") && (($r1.data.planned_duration ?? -1) == 20) && ($r1.set_count == 2))
    }

    // c2 — text-only keeps all four time fields and actor_fields (T-SAFE-01-2)
    function.run "journey/cell_merge_patch" {
      input = {cell: $cell, patch: {content: "Load and strap the truck"}}
    } as $r2

    var $r2_task {
      value = $r2.data.actor_fields|get:"task_objective":null
    }

    var $c2 {
      value = ((($r2.data.content ?? "__null__") == "Load and strap the truck") && (($r2.data.time_duration_value ?? -1) == 20) && (($r2.data.time_duration_unit ?? "__null__") == "minutes") && (($r2.data.planned_duration ?? -1) == 20) && (($r2.data.actual_duration ?? -1) == 25) && (($r2_task ?? "__null__") == "x") && ($r2.set_count == 1))
    }

    // c3 — empty string clears the text (T-SAFE-01-3)
    function.run "journey/cell_merge_patch" {
      input = {cell: $cell, patch: {content: ""}}
    } as $r3

    var $c3 {
      value = ((($r3.data.content ?? "__null__") == "") && ($r3.set_count == 1))
    }

    // c4 — null keeps the text (T-SAFE-01-4)
    function.run "journey/cell_merge_patch" {
      input = {cell: $cell, patch: {content: null}}
    } as $r4

    var $c4 {
      value = ((($r4.data.content ?? "__null__") == "Load the truck") && ($r4.set_count == 0))
    }

    // c5 — a sent zero is stored as zero (T-SAFE-01-5)
    function.run "journey/cell_merge_patch" {
      input = {cell: $cell, patch: {planned_duration: 0}}
    } as $r5

    var $c5 {
      value = ((($r5.data.planned_duration ?? -1) == 0) && (($r5.data.content ?? "__null__") == "Load the truck") && ($r5.set_count == 1))
    }

    // c6 — nothing sent sets nothing (T-SAFE-01-6)
    function.run "journey/cell_merge_patch" {
      input = {cell: $cell, patch: {stage_key: "s1", lens_key: "l1"}}
    } as $r6

    var $c6 {
      value = ((($r6.data.content ?? "__null__") == "Load the truck") && (($r6.data.actual_duration ?? -1) == 25) && ($r6.set_count == 0))
    }

    // c7 — text is trimmed
    function.run "journey/cell_merge_patch" {
      input = {cell: $cell, patch: {content: "  Hi  "}}
    } as $r7

    var $c7 {
      value = (($r7.data.content ?? "__null__") == "Hi")
    }

    // c8 — actor_fields sent is passed through (db.patch then merges it into the stored json)
    function.run "journey/cell_merge_patch" {
      input = {cell: $cell, patch: {actor_fields: {success_criteria: "y"}}}
    } as $r8

    var $r8_crit {
      value = $r8.data.actor_fields|get:"success_criteria":null
    }

    var $c8 {
      value = ((($r8_crit ?? "__null__") == "y") && ($r8.set_count == 1))
    }

    var $all_pass {
      value = ($c1 && $c2 && $c3 && $c4 && $c5 && $c6 && $c7 && $c8)
    }
  }

  response = {
    all_pass: $all_pass
    cases   : {c1: $c1, c2: $c2, c3: $c3, c4: $c4, c5: $c5, c6: $c6, c7: $c7, c8: $c8}
  }
}
