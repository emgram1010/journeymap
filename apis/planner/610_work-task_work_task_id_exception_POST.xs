// EXC-1 (US-EXC-1-03) — "This part of the job is leaving the happy path."
// Starts a CHILD JOB on the map that the parent map's `exception` link
// points to, pinned to that map's latest published version, tied back to
// the parent job and step, carrying the item counts that left.
//
// THE PARENT DOES NOT STOP (D-1). Nothing here blocks the parent unless
// the caller explicitly asks (`also_block_parent`), and then it goes
// through LOG-1's own engine (log/record_task_event, soft mode): a
// refused transition (e.g. the step is already done) does NOT fail the
// spawn — it is logged as rejected and the response says
// parent_blocked = false.
//
// THE LINK IS READ FROM THE JOB'S PINNED VERSION, never the live map: a
// job runs on the version it started with. Stage-matched, ANY lens (D-10).
// `exception` links only (D-6). The target is pinned at its LATEST
// published version (D-2). No plan acceptance is required for the
// target (D-3) — the backlog/work-item lists (558/559) do not filter by
// planner_workspace_map, so nothing needs inserting.
//
// THE ONE SANCTIONED BYPASS OF EST-1's FREEZE (E-EST-007). Once work has
// started, only this endpoint may change a job's order lines, and only
// by moving counts to a child: every such change has a work_item_exception
// row and a `lines_moved` success event naming it.
//
// ORDER OF WORK: every check first; every pure function.run (split,
// tasks_from_version, estimate) before the transaction; ONE transaction
// for the child job + its tasks (jobs/create_job — the same function 554
// uses), the child's lines, the parent's line edits (by id, in a loop)
// and the exception row. A function.run inside db.transaction rolls back
// with it (verified live, 2026-10-26). Then, outside: slot refresh
// (estimate/refresh_job_slots — the same function 607 uses), the `note`
// on the parent step, the optional block, and the events.
//
// ONE SEND PER REQUEST (Opus review). The client sends one
// correlation_id per opened sheet and reuses it on retry. A repeat is
// refused as E-EXC-013 ("already sent"), checked up front AND
// again inside the transaction, where `child_job_created` is logged so the
// marker commits atomically with the job it names.
//
// TWO SENDS AT ONCE CAN'T OVER-MOVE. Xano's transaction does NOT
// serialize overlapping requests (verified live), so the guard is the
// database's own: each send writes parent_seq = (exceptions on this
// parent when its checks read the order) + 1, and (parent_work_item_id,
// parent_seq) is UNIQUE.
// Two overlapping sends compute the same number; the second insert is
// refused, its whole transaction rolls back, and it is reported as
// E-EXC-012. The lines re-read inside the transaction still catches a
// send that starts after another has committed.
//
// AFTER THE COMMIT, NOTHING CAN TURN A SAVED SEND INTO AN ERROR: the
// follow-up work (estimate, slots, feed note, block) runs in its own
// try_catch; a failure there is logged `failed` and the response still
// reports the child (followup_failed = true).
//
// A FAILURE INSIDE THE TRANSACTION IS CAUGHT, LOGGED AS `failed` WITH A
// REFERENCE, AND RE-RAISED — nothing half-written survives (FT-EXC-1-G02).
//
// Never fails silently: every refusal logs `exception_raised` /
// `rejected` with its E-EXC code; success logs exception_raised,
// child_job_created and (when counts moved) lines_moved.
query "work-task/{work_task_id}/exception" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int work_task_id filters=min:1
    int target_map_id filters=min:1
    // Optional at the schema level ONLY so a missing reason gets the
    // friendly E-EXC-010 instead of a raw "Missing param".
    text reason_code? filters=trim
    text note? filters=trim
    // [{item_type_id, quantity}] — omit (or []) for a whole-job exception.
    json lines?
    // Block the parent step too, through LOG-1. Off by default (D-1);
    // omitted and false mean the same thing, so no raw-input check.
    bool also_block_parent?
    // manual (default) | ai | system — PRD EX-9's hook for the AI run path.
    text source? filters=trim
    // Optional override of the generated child title.
    text title? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = false
    } as $raw_input

    db.get work_task {
      field_name = "id"
      field_value = $input.work_task_id
    } as $task

    precondition ($task != null) {
      error_type = "notfound"
      error = "Step not found"
    }

    db.get work_item {
      field_name = "id"
      field_value = $task.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Step not found"
    }

    db.get planner_workspace {
      field_name = "id"
      field_value = $job.workspace_id
    } as $workspace

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $workspace.is_archived ?? false
        feature    : "EXC-1"
        step       : "exception_raised"
        entity_type: "planner_workspace"
        entity_id  : $job.workspace_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    // ── A retry of a send that already saved (E-EXC-013) ───────────────
    var $request_id {
      value = $input.correlation_id ?? ""
    }

    var $has_request_id {
      value = ($request_id != "")
    }

    db.query event_log {
      where = ($has_request_id == true) && $db.event_log.correlation_id == $request_id && $db.event_log.feature == "EXC-1" && $db.event_log.step == "child_job_created" && $db.event_log.outcome == "success" && $db.event_log.account_id == $actor.account_id
      return = {type: "list"}
    } as $prior_sends

    var $prior_send {
      value = $prior_sends|first
    }

    var $prior_child_id {
      value = $prior_send.entity_id ?? 0
    }

    db.get work_item_exception {
      field_name = "child_work_item_id"
      field_value = $prior_child_id
    } as $prior_exception

    var $already_sent {
      value = ($prior_child_id != 0 && ($prior_exception.parent_work_task_id ?? 0) == $task.id)
    }

    conditional {
      if ($already_sent == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "EXC-1"
            step          : "exception_raised"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : "E-EXC-013"
            message       : "Send to linked map repeated; the first one already saved."
            metadata      : {work_item_id: $job.id, child_work_item_id: $prior_child_id}
          }
        }
      }
    }

    precondition ($already_sent == false) {
      error_type = "inputerror"
      error = "This was already sent. Reopen the job to see it. (E-EXC-013)"
    }

    var $source {
      value = "manual"
    }

    conditional {
      if ($input.source == "ai" || $input.source == "system") {
        var.update $source {
          value = $input.source
        }
      }
    }

    // Lines: present only when the caller sent the key (an omitted json
    // input is not reliably null — CLAUDE.md). A non-array is refused
    // below as E-EXC-006, the same as any other junk count.
    var $lines_in {
      value = []
    }

    var $lines_is_array {
      value = true
    }

    conditional {
      if ($raw_input|has:"lines") {
        var $lines_json {
          value = ($input.lines ?? null)|json_encode
        }

        var $lines_starts_array {
          value = "/^[[]/"|regex_matches:$lines_json
        }

        var.update $lines_is_array {
          value = ($lines_starts_array == true || $lines_json == "null")
        }

        conditional {
          if ($lines_starts_array == true) {
            var.update $lines_in {
              value = $input.lines
            }
          }
        }
      }
    }

    var $moved_requested {
      value = ($lines_is_array == true) ? ($lines_in|count) : 1
    }

    // ── The pinned version, its exception links for this step's stage ──
    db.get journey_map_version {
      field_name = "id"
      field_value = $job.journey_map_version_id
    } as $parent_version

    var $parent_snapshot {
      value = $parent_version.snapshot ?? {}
    }

    var $parent_has_items_row {
      value = (($parent_snapshot.schema_version ?? 1) >= 2)
    }

    var $matching_links {
      value = []
    }

    foreach ($parent_snapshot.links ?? []) {
      each as $pl {
        conditional {
          if ($pl.link_type == "exception" && $pl.stage_key == $task.stage_key && $pl.target_map_id == $input.target_map_id) {
            array.push $matching_links {
              value = $pl
            }
          }
        }
      }
    }

    var $link_found {
      value = (($matching_links|count) > 0)
    }

    var $stage_label {
      value = $task.stage_key
    }

    foreach ($parent_snapshot.stages ?? []) {
      each as $ps {
        conditional {
          if ($ps.key == $task.stage_key) {
            var.update $stage_label {
              value = $ps.label ?? $task.stage_key
            }
          }
        }
      }
    }

    // ── The target map and its latest published version ────────────────
    db.get journey_map {
      field_name = "id"
      field_value = $input.target_map_id
    } as $target_map

    var $target_title {
      value = $target_map.title ?? "that map"
    }

    var $target_ok {
      value = ($target_map != null && $target_map.account_id == $actor.account_id)
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $input.target_map_id
      sort = {journey_map_version.version_no: "desc"}
      return = {type: "list"}
    } as $target_versions

    var $target_version_count {
      value = $target_versions|count
    }

    var $target_version {
      value = $target_versions|first
    }

    var $target_has_items_row {
      value = (($target_version.snapshot.schema_version ?? 1) >= 2)
    }

    // ── The parent's lines, with keys and labels ───────────────────────
    db.query work_item_line {
      where = $db.work_item_line.work_item_id == $job.id
      sort = {work_item_line.id: "asc"}
      return = {type: "list"}
    } as $parent_line_rows

    // The race guard's number, counted HERE with the lines every check
    // is made against, not inside the transaction: counted later, a twin
    // send that committed in between is simply counted and both succeed
    // (seen live). Two sends that saw the same order claim the same N.
    db.query work_item_exception {
      where = $db.work_item_exception.parent_work_item_id == $job.id
      return = {type: "count"}
    } as $prior_exceptions

    // What every check below is made against; re-read in the transaction.
    var $lines_fp_before {
      value = ""
    }

    foreach ($parent_line_rows) {
      each as $fpr {
        var.update $lines_fp_before {
          value = $lines_fp_before ~ ($fpr.id|to_text) ~ ":" ~ ($fpr.quantity|to_text) ~ ";"
        }
      }
    }

    var $item_ids {
      value = [-1]
    }

    foreach ($parent_line_rows) {
      each as $plr {
        array.push $item_ids {
          value = $plr.item_type_id
        }
      }
    }

    db.query item_type {
      where = $db.item_type.id in $item_ids
      return = {type: "list"}
    } as $item_rows

    var $item_by_id {
      value = {}
    }

    foreach ($item_rows) {
      each as $ir {
        var $ir_key {
          value = $ir.id|to_text
        }

        var.update $item_by_id {
          value = $item_by_id|set:$ir_key:$ir
        }
      }
    }

    var $parent_lines {
      value = []
    }

    foreach ($parent_line_rows) {
      each as $plr2 {
        var $plr2_key {
          value = $plr2.item_type_id|to_text
        }

        var $plr2_item {
          value = $item_by_id|get:$plr2_key:null
        }

        array.push $parent_lines {
          value = {item_type_id: $plr2.item_type_id, item_key: $plr2_item.key ?? "", quantity: $plr2.quantity}
        }
      }
    }

    function.run "exceptions/split_lines" {
      input = {parent_lines: $parent_lines, moved: $lines_in}
    } as $split

    var $child_line_count {
      value = $split.child_lines|count
    }

    // ── Verdict: one code, one message, one log, one raise ─────────────
    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($job.status == "cancelled" || $job.status == "completed") {
        var.update $reject_code {
          value = "E-EXC-001"
        }

        var.update $reject_msg {
          value = "That job is finished or cancelled, so nothing can be sent from it or added under it. (E-EXC-001)"
        }
      }
    }

    var $reason_ok {
      value = ($input.reason_code == "waiting_on_someone" || $input.reason_code == "missing_information" || $input.reason_code == "something_went_wrong" || $input.reason_code == "other")
    }

    conditional {
      if ($reject_code == "" && $reason_ok == false) {
        var.update $reject_code {
          value = "E-EXC-010"
        }

        var.update $reject_msg {
          value = "Pick a reason. (E-EXC-010)"
        }
      }
    }

    var $note_text {
      value = $input.note ?? ""
    }

    var $note_has_html {
      value = "/<[a-zA-Z][^>]*>/"|regex_matches:$note_text
    }

    var $note_len {
      value = $note_text|strlen
    }

    conditional {
      if ($reject_code == "" && ($note_len > 500 || $note_has_html == true)) {
        var.update $reject_code {
          value = "E-EXC-011"
        }

        var.update $reject_msg {
          value = "Keep the note under 500 characters, with no HTML. (E-EXC-011)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($link_found == false || $target_ok == false)) {
        var.update $reject_code {
          value = "E-EXC-002"
        }

        var.update $reject_msg {
          value = "This step doesn't send work to that map. Add an exception link on the map and publish a new version — new jobs will have it. (E-EXC-002)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $target_version_count == 0) {
        var.update $reject_code {
          value = "E-EXC-003"
        }

        var.update $reject_msg {
          value = "'" ~ $target_title ~ "' hasn't been published yet. Publish it, then try again. (E-EXC-003)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $moved_requested > 0 && $parent_has_items_row == false) {
        var.update $reject_code {
          value = "E-EXC-004"
        }

        var.update $reject_msg {
          value = "This work type doesn't track items, so you can't pick which ones to send. Send the whole step instead. (E-EXC-004)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $lines_is_array == false) {
        var.update $reject_code {
          value = "E-EXC-006"
        }

        var.update $reject_msg {
          value = "Enter how many to send, from 1 up to how many are on the order. (E-EXC-006)"
        }
      }
    }

    // One literal message per code (the error-code registry test pairs
    // each code with the sentence beside it — a nested ternary hid that).
    conditional {
      if ($reject_code == "" && $split.ok == false && $split.code == "E-EXC-005") {
        var.update $reject_code {
          value = "E-EXC-005"
        }

        var.update $reject_msg {
          value = "That item isn't on this order. (E-EXC-005)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $split.ok == false && $split.code == "E-EXC-007") {
        var.update $reject_code {
          value = "E-EXC-007"
        }

        var.update $reject_msg {
          value = "That item is listed twice — combine them. (E-EXC-007)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $split.ok == false) {
        var.update $reject_code {
          value = "E-EXC-006"
        }

        var.update $reject_msg {
          value = "Enter how many to send, from 1 up to how many are on the order. (E-EXC-006)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $child_line_count > 0 && $target_has_items_row == false) {
        var.update $reject_code {
          value = "E-EXC-008"
        }

        var.update $reject_msg {
          value = "'" ~ $target_title ~ "' doesn't track items, so the counts can't go with the work. Add an Items row to it and publish, or send without counts. (E-EXC-008)"
        }
      }
    }

    // ── The child's title (US-EXC-1-08's rule; childTitle() is its twin) ─
    var $title_override {
      value = $input.title ?? ""
    }

    var $override_has_html {
      value = ("/<[a-zA-Z][^>]*>/"|regex_matches:$title_override)
    }

    conditional {
      if ($reject_code == "" && (($title_override|strlen) > 120 || $override_has_html == true)) {
        var.update $reject_code {
          value = "E-JOB-001"
        }

        var.update $reject_msg {
          value = "Give the job a short title (up to 120 characters). (E-JOB-001)"
        }
      }
    }

    var $moved_total {
      value = 0
    }

    var $first_moved_label {
      value = ""
    }

    foreach ($split.child_lines) {
      each as $cl {
        var.update $moved_total {
          value = $moved_total + $cl.quantity
        }
      }
    }

    conditional {
      if ($child_line_count == 1) {
        var $only_line {
          value = $split.child_lines|first
        }

        var $only_key {
          value = $only_line.item_type_id|to_text
        }

        var $only_item {
          value = $item_by_id|get:$only_key:null
        }

        var.update $first_moved_label {
          value = $only_item.label ?? $only_line.item_key
        }
      }
    }

    var $title_suffix {
      value = ""
    }

    conditional {
      if ($child_line_count == 1) {
        var.update $title_suffix {
          value = " (" ~ ($moved_total|to_text) ~ " " ~ $first_moved_label ~ ")"
        }
      }

      elseif ($child_line_count > 1) {
        var.update $title_suffix {
          value = " (" ~ ($moved_total|to_text) ~ " items)"
        }
      }
    }

    var $title_base {
      value = ($job.title|trim) ~ " · " ~ ($target_title|trim)
    }

    var $title_room {
      value = 120 - ($title_suffix|strlen)
    }

    conditional {
      if (($title_base|strlen) > $title_room) {
        var.update $title_base {
          value = ($title_base|substr:0:$title_room)|trim
        }
      }
    }

    var $child_title {
      value = $title_base ~ $title_suffix
    }

    conditional {
      if ($title_override != "") {
        var.update $child_title {
          value = $title_override
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "EXC-1"
            step          : "exception_raised"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Send to linked map refused."
            metadata      : {work_item_id: $job.id, target_map_id: $input.target_map_id, source: $source}
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // ── Everything pure, before the transaction ────────────────────────
    function.run "jobs/tasks_from_version" {
      input = {snapshot: $target_version.snapshot}
    } as $child_plan

    // The child carries the parent's attributes, each marked as coming
    // from the parent (D-8). Written once, on db.add — never patched.
    var $parent_source_label {
      value = "parent #" ~ ($job.id|to_text)
    }

    var $parent_attrs {
      value = $job.attributes ?? {}
    }

    var $child_attrs {
      value = {}
    }

    var $parent_attr_keys {
      value = $parent_attrs|keys
    }

    foreach ($parent_attr_keys) {
      each as $ak {
        var $attr_entry {
          value = $parent_attrs|get:$ak:null
        }

        // 554 doesn't check attribute shape, so a value may be plain text
        // ({"po":"123"}); wrap it rather than `|set` on a string. A var
        // ternary, not a conditional: no branching on a var set this pass.
        var $attr_json {
          value = $attr_entry|json_encode
        }

        var $attr_is_obj {
          value = "/^[{]/"|regex_matches:$attr_json
        }

        var $attr_value {
          value = (($attr_is_obj == true) ? ($attr_entry|set:"source":$parent_source_label) : {value: $attr_entry, source: $parent_source_label})
        }

        var.update $child_attrs {
          value = $child_attrs|set:$ak:$attr_value
        }
      }
    }

    // The parent's line edits, decided here as DATA (one op per existing
    // line), so the transaction loop branches only on its loop item.
    var $after_by_id {
      value = {}
    }

    foreach ($split.parent_after) {
      each as $pa {
        var $pa_key {
          value = $pa.item_type_id|to_text
        }

        var.update $after_by_id {
          value = $after_by_id|set:$pa_key:$pa.quantity
        }
      }
    }

    var $line_ops {
      value = []
    }

    foreach ($parent_line_rows) {
      each as $row {
        var $row_key {
          value = $row.item_type_id|to_text
        }

        var $row_after {
          value = ($after_by_id|get:$row_key:null) ?? 0
        }

        // Hoisted, never inline: a ternary written as an object-literal
        // value silently drops every key after it (found live on the first
        // spawn — the parent kept all its counts). See CLAUDE.md.
        var $row_action {
          value = (($row_after == 0) ? "del" : (($row_after != $row.quantity) ? "patch" : "keep"))
        }

        array.push $line_ops {
          value = {line_id: $row.id, action: $row_action, quantity: $row_after}
        }
      }
    }

    var $moved_lines_record {
      value = $split.child_lines
    }

    var $exception_created_by {
      value = (($source == "manual") ? $actor.user_id : 0)
    }

    // ── ONE transaction ─────────────────────────────────────────────────
    var $child_id {
      value = 0
    }

    var $exception_id {
      value = 0
    }

    var $tx_failed {
      value = false
    }

    var $tx_stale {
      value = false
    }

    var $tx_dup {
      value = false
    }

    var $seq_claimed {
      value = 0
    }

    try_catch {
      try {
        group {
          stack {
            db.transaction {
              stack {
                db.query event_log {
                  where = ($has_request_id == true) && $db.event_log.correlation_id == $request_id && $db.event_log.feature == "EXC-1" && $db.event_log.step == "child_job_created" && $db.event_log.outcome == "success" && $db.event_log.account_id == $actor.account_id
                  return = {type: "count"}
                } as $dup_count

                db.query work_item_line {
                  where = $db.work_item_line.work_item_id == $job.id
                  sort = {work_item_line.id: "asc"}
                  return = {type: "list"}
                } as $lines_now

                var $lines_fp_now {
                  value = ""
                }

                foreach ($lines_now) {
                  each as $fpn {
                    var.update $lines_fp_now {
                      value = $lines_fp_now ~ ($fpn.id|to_text) ~ ":" ~ ($fpn.quantity|to_text) ~ ";"
                    }
                  }
                }

                var.update $tx_dup {
                  value = ($dup_count > 0)
                }

                var.update $tx_stale {
                  value = ($lines_fp_now != $lines_fp_before)
                }

                precondition ($tx_dup == false && $tx_stale == false) {
                  error = "Send overtaken by another change."
                }

                function.run "jobs/create_job" {
                  input = {
                    account_id            : $job.account_id
                    workspace_id          : $job.workspace_id
                    journey_map_version_id: $target_version.id
                    title                 : $child_title
                    attributes            : $child_attrs
                    parent_work_item_id   : $job.id
                    created_by            : $actor.user_id
                    tasks                 : $child_plan.tasks
                  }
                } as $child

                foreach ($split.child_lines) {
                  each as $cl2 {
                    db.add work_item_line {
                      data = {
                        created_at      : "now"
                        work_item_id    : $child.id
                        item_type_id    : $cl2.item_type_id
                        quantity        : $cl2.quantity
                        flagged_quantity: 0
                        created_by      : $actor.user_id
                      }
                    } as $_child_line
                  }
                }

                foreach ($line_ops) {
                  each as $op {
                    conditional {
                      if ($op.action == "del") {
                        db.del work_item_line {
                          field_name = "id"
                          field_value = $op.line_id
                        }
                      }
                    }

                    conditional {
                      if ($op.action == "patch") {
                        db.patch work_item_line {
                          field_name = "id"
                          field_value = $op.line_id
                          data = {quantity: $op.quantity}
                        } as $_patched_line
                      }
                    }
                  }
                }

                // Race guard: see the header. A twin send claims the same
                // number and the unique index refuses one of them.
                var.update $seq_claimed {
                  value = $prior_exceptions + 1
                }

                db.add work_item_exception {
                  data = {
                    parent_seq         : $seq_claimed
                    created_at         : "now"
                    account_id         : $job.account_id
                    parent_work_item_id: $job.id
                    parent_work_task_id: $task.id
                    child_work_item_id : $child.id
                    stage_key          : $task.stage_key
                    lens_key           : $task.lens_key
                    link_type          : "exception"
                    target_map_id      : $input.target_map_id
                    target_version_id  : $target_version.id
                    reason_code        : $input.reason_code
                    note               : $input.note ?? ""
                    moved_lines        : $moved_lines_record
                    parent_blocked     : false
                    source             : $source
                    created_by         : $exception_created_by
                  }
                } as $exception_row

                var.update $child_id {
                  value = $child.id
                }

                var.update $exception_id {
                  value = $exception_row.id
                }

                // Inside the transaction ON PURPOSE: it is the retry marker
                // (E-EXC-013), so it commits or rolls back with the job.
                function.run "ops/log_event" {
                  input = {
                    feature       : "EXC-1"
                    step          : "child_job_created"
                    outcome       : "success"
                    severity      : "info"
                    user_id       : $actor.user_id
                    account_id    : $actor.account_id
                    entity_type   : "work_item"
                    entity_id     : $child.id
                    correlation_id: $input.correlation_id
                    message       : "Child job created from an exception."
                    metadata      : {parent_work_item_id: $job.id, journey_map_version_id: $target_version.id, task_count: ($child_plan.tasks|count)}
                  }
                }
              }
            }
          }
        }
      }

      catch {
        var.update $tx_failed {
          value = true
        }
      }
    }

    // A failed write whose claimed number now exists lost the race to a
    // twin send that committed: report it as "the order changed".
    db.query work_item_exception {
      where = $db.work_item_exception.parent_work_item_id == $job.id && $db.work_item_exception.parent_seq == $seq_claimed
      return = {type: "count"}
    } as $seq_taken

    var $lost_race {
      value = ($tx_failed == true && $seq_claimed > 0 && $seq_taken > 0 && $tx_dup == false)
    }

    var.update $tx_stale {
      value = ($tx_stale == true || $lost_race == true)
    }

    var $overtaken {
      value = ($tx_dup == true || $tx_stale == true)
    }

    var $overtaken_code {
      value = (($tx_dup == true) ? "E-EXC-013" : "E-EXC-012")
    }

    conditional {
      if ($tx_failed == true && $overtaken == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "EXC-1"
            step          : "exception_raised"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            error_code    : $overtaken_code
            message       : "Send to linked map overtaken by another send; nothing was saved."
            metadata      : {work_item_id: $job.id, target_map_id: $input.target_map_id}
          }
        }
      }
    }

    precondition ($tx_dup == false) {
      error_type = "inputerror"
      error = "This was already sent. Reopen the job to see it. (E-EXC-013)"
    }

    precondition ($tx_stale == false) {
      error_type = "inputerror"
      error = "The order changed while you were sending. Close this and try again. (E-EXC-012)"
    }

    conditional {
      if ($tx_failed == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "EXC-1"
            step          : "exception_raised"
            outcome       : "failure"
            severity      : "error"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $input.work_task_id
            correlation_id: $input.correlation_id
            message       : "Send to linked map failed while writing; nothing was saved."
            metadata      : {work_item_id: $job.id, target_map_id: $input.target_map_id, target_version_id: $target_version.id}
          }
        }
      }
    }

    precondition ($tx_failed == false) {
      error = "That didn't save, and nothing was changed. Try again; if it keeps happening, quote the Reference to support."
    }

    // ── After the commit: slots, the parent's activity feed, the block ──
    // Defaults first: a follow-up failure must still return the child.
    var $refreshed {
      value = {refreshed_count: 0, tweaked_skipped_count: 0}
    }

    var $parent_estimate {
      value = null
    }

    var $parent_blocked {
      value = false
    }

    var $block_refusal {
      value = ""
    }

    var $note_written {
      value = false
    }

    var $followup_failed {
      value = false
    }

    var $reason_words {
      value = $input.reason_code|replace:"_":" "
    }

    var $count_words {
      value = (($child_line_count == 0) ? "" : (" (" ~ ($moved_total|to_text) ~ " items)"))
    }

    var $feed_note {
      value = "Sent to " ~ $target_title ~ " → job #" ~ ($child_id|to_text) ~ $count_words ~ ". Reason: " ~ $reason_words ~ "."
    }

    var $note_client_id {
      value = "exc-" ~ ($exception_id|to_text) ~ "-note"
    }

    var $block_note {
      value = "Sent " ~ (($child_line_count == 0) ? "this step" : (($moved_total|to_text) ~ " items")) ~ " to " ~ $child_title ~ " (#" ~ ($child_id|to_text) ~ ")"
    }

    var $block_client_id {
      value = "exc-" ~ ($exception_id|to_text) ~ "-block"
    }

    try_catch {
      try {
        group {
          stack {
            conditional {
              if ($child_line_count > 0) {
                function.run "estimate/estimate_job" {
                  input = {work_item_id: $job.id}
                } as $parent_estimate_after

                function.run "estimate/refresh_job_slots" {
                  input = {
                    work_item_id  : $job.id
                    estimate      : $parent_estimate_after
                    user_id       : $actor.user_id
                    account_id    : $actor.account_id
                    feature       : "EXC-1"
                    message       : "Items were sent to a linked map, but a scheduled slot keeps its tweaked duration."
                    correlation_id: $input.correlation_id
                  }
                } as $refresh_result

                var.update $refreshed {
                  value = $refresh_result
                }
              }
            }

            function.run "estimate/estimate_job" {
              input = {work_item_id: $job.id}
            } as $estimate_now

            var.update $parent_estimate {
              value = $estimate_now
            }

            // The fork shows in the parent step's own activity feed — a
            // `note` through LOG-1's engine, no new event type. system_note:
            // the assignment rule is about performers recording their own
            // work; this note is the system's, so it is written even when a
            // member sends from someone else's step (Opus review).
            // reason_code is passed explicitly as "": an omitted function
            // input silently INHERITS the caller's input of the same name.
            function.run "log/record_task_event" {
              input = {
                actor          : $actor
                work_task_id   : $task.id
                event_type     : "note"
                reason_code    : ""
                note           : $feed_note
                client_event_id: $note_client_id
                correlation_id : $input.correlation_id
                source         : $source
                soft           : true
                system_note    : true
              }
            } as $note_result

            var.update $note_written {
              value = ($note_result.rejected == false)
            }

            // The block is NOT a system note: blocking someone else's step
            // still needs the assignment rule, and its refusal is reported.
            conditional {
              if ($input.also_block_parent == true) {
                function.run "log/record_task_event" {
                  input = {
                    actor          : $actor
                    work_task_id   : $task.id
                    event_type     : "blocked"
                    reason_code    : $input.reason_code
                    note           : $block_note
                    client_event_id: $block_client_id
                    correlation_id : $input.correlation_id
                    source         : $source
                    soft           : true
                    system_note    : false
                  }
                } as $block_result

                var.update $parent_blocked {
                  value = ($block_result.rejected == false)
                }

                var.update $block_refusal {
                  value = $block_result.message
                }
              }
            }

            // The one field this append-only row ever gets after its
            // insert: whether the optional block actually happened.
            conditional {
              if ($parent_blocked == true) {
                db.patch work_item_exception {
                  field_name = "id"
                  field_value = $exception_id
                  data = {parent_blocked: true}
                } as $_exc_blocked
              }
            }
          }
        }
      }

      catch {
        var.update $followup_failed {
          value = true
        }
      }
    }

    conditional {
      if ($followup_failed == true) {
        function.run "ops/log_event" {
          input = {
            feature       : "EXC-1"
            step          : "exception_followup"
            outcome       : "failure"
            severity      : "error"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $job.id
            correlation_id: $input.correlation_id
            message       : "The send saved, but a follow-up step (estimate, slots, feed note or block) failed."
            metadata      : {exception_id: $exception_id, child_work_item_id: $child_id, note_written: $note_written, parent_blocked: $parent_blocked}
          }
        }
      }
    }

    conditional {
      if ($followup_failed == false && $note_written == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "EXC-1"
            step          : "exception_followup"
            outcome       : "failure"
            severity      : "warn"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_task"
            entity_id     : $task.id
            correlation_id: $input.correlation_id
            message       : "The send saved, but its note on the parent step was refused."
            metadata      : {exception_id: $exception_id, child_work_item_id: $child_id}
          }
        }
      }
    }

    conditional {
      if ($child_line_count > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "EXC-1"
            step          : "lines_moved"
            outcome       : "success"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $job.id
            correlation_id: $input.correlation_id
            message       : "Order lines moved to a child job (the one sanctioned change after work starts)."
            metadata      : {parent_work_item_id: $job.id, child_work_item_id: $child_id, exception_id: $exception_id, moved_lines: $moved_lines_record, refreshed_count: $refreshed.refreshed_count, tweaked_skipped_count: $refreshed.tweaked_skipped_count}
          }
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature       : "EXC-1"
        step          : "exception_raised"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "work_task"
        entity_id     : $task.id
        correlation_id: $input.correlation_id
        message       : "Work sent to a linked map."
        metadata      : {exception_id: $exception_id, child_work_item_id: $child_id, target_map_id: $input.target_map_id, target_version_id: $target_version.id, moved_count: $moved_total, parent_blocked: $parent_blocked, block_refusal: $block_refusal, note_written: $note_written, followup_failed: $followup_failed, source: $source}
      }
    }

    db.query work_item_line {
      where = $db.work_item_line.work_item_id == $job.id
      return = {type: "list"}
    } as $lines_after
  }

  response = {
    exception_id  : $exception_id
    child         : {work_item_id: $child_id, title: $child_title, journey_map_version_id: $target_version.id, version_no: $target_version.version_no, status: "open", task_count: ($child_plan.tasks|count), lines: $split.child_lines}
    parent        : {work_item_id: $job.id, lines_after: $lines_after, estimate: $parent_estimate, refreshed_count: $refreshed.refreshed_count, tweaked_skipped_count: $refreshed.tweaked_skipped_count}
    parent_blocked: $parent_blocked
    block_refusal : $block_refusal
    followup_failed: $followup_failed
  }
}
