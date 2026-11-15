// IL-00-03: MCP tool — scaffold a journey map's structure.
// Delegates to the existing scaffold_structure tool.
//
// COP-1 story 06 (2026-11-15): this used to be a 436-line COPY of scaffold_structure, written
// before ORD-2 rewrote that tool. The copy still had the old defects: it crashed with
// "Unable to locate var: op.primary_actor_lens" when an optional field was left out, a rename
// overwrote stage_goal / primary_actor_lens with nothing when they were not sent, and a remove
// deleted the stage row directly instead of going through journey/remove_stage (its cells and
// dependants were left behind). It now simply calls scaffold_structure, so there is one
// implementation and one set of fixes. The gate still runs first under THIS tool's name; the
// inner tool records its own audit row too.
//
// Behaviour change: `position` on a stage operation is no longer read (scaffold_structure always
// appends). Use mutate_structure with after_stage_key / after_lens_key to place a column or row.
tool scaffold_map {
  instructions = "Apply a structural blueprint to a journey map in one call. Pass journey_map_id, stage_operations (array of {action, key?, label, stage_goal?, primary_actor_lens?}), and lens_operations (array of {action, key?, label, actor_type?}). Actions: 'rename', 'add', 'remove'. For rename, stage_goal (exit condition one-liner) and primary_actor_lens (lens key that owns the stage, e.g. lens-3) are optional extras; a field you leave out is left alone. Adds append to the end. All or nothing: if any key is not in the map, or any step fails, nothing is changed and the error names the key or step. Returns counts of stages/lenses added/renamed/removed and cells created."

  input {
    int journey_map_id filters=min:1
    json stage_operations?
    json lens_operations?

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce.
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, ticket: $input.ticket, tool: "scaffold_map", kind: "write"}
    } as $cop1_gate

    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    // RES-6-04: hard cap on each operation array to bound execution time.
    precondition ($input.stage_operations == null || ($input.stage_operations|count) <= 500) {
      error_type = "inputerror"
      error = "Batch too large — max 500 stage_operations per call. Split into multiple calls."
    }

    precondition ($input.lens_operations == null || ($input.lens_operations|count) <= 500) {
      error_type = "inputerror"
      error = "Batch too large — max 500 lens_operations per call. Split into multiple calls."
    }

    tool.call scaffold_structure {
      input = {
        journey_map_id  : $input.journey_map_id
        stage_operations: $input.stage_operations
        lens_operations : $input.lens_operations
        ticket          : $input.ticket
      }
    } as $r

    // COP-1 (2026-11-14): a refused inner call does NOT throw through tool.call — $r comes back as
    // {code, message, payload} instead of the success fields (found live). Pass the inner
    // message on instead of crashing on $r.errors.
    var $inner_ok {
      value = ($r|has:"success")
    }

    var $inner_msg {
      value = $r|get:"message":"The bulk map change was refused; nothing was changed."
    }

    precondition ($inner_ok == true) {
      error_type = "inputerror"
      error = $inner_msg
    }

    var $errs {
      value = $r.errors
    }
  }

  response = {
    success       : $r.success
    stages_added  : $r.stages_added
    stages_removed: $r.stages_removed
    stages_renamed: $r.stages_renamed
    lenses_added  : $r.lenses_added
    lenses_removed: $r.lenses_removed
    lenses_renamed: $r.lenses_renamed
    cells_created : $r.cells_created
    cells_deleted : $r.cells_deleted
    errors        : $errs
    failed        : $errs
    failed_count  : $errs|count
  }
}
