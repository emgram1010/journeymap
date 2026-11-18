// COP-9 stories 02/03/04/08 — THE one writer for the copilot's skill library ("how I work"). The
// copilot's tools (save_skill, retire_skill) and nothing else call it; it never deletes - the
// copilot retires.
//
// op "create": a new skill / exception / lesson / link, on trial, with a draft map in the
//   account's copilot home so it shows in "how I work".
// op "edit": new text for an existing item. An empty field keeps what is there (kind never changes).
// op "retire": stops it loading. Undo (copilot/skill_undo) can bring it back.
//
// Refusals, all logged as "rejected" before they are raised (as input errors, so the plain
// message and its code always reach the copilot and the screen), and nothing is stored:
//   E-COP-081 - anything outside the account's own copilot home: an item, a parent or linked
//               skill, or a scope (business / map) that is not this account's. No home = refused (E-COP-086).
//   E-COP-084 - an exception with no "when", or not attached to one skill.
//   E-COP-082 / E-COP-083 - the hard limits (copilot/skill_limits), checked HERE on the server,
//               before the first write, at every approval level.
//
// COP-11 (locks, kinds of work, size limit) adds, all checked here on the server before the first write:
//   E-COP-089 - the copilot tries to edit or retire a LOCKED item (copilot_skill_meta). The owner's own
//               text is locked by default (D-24-1) unless let_ai_change is ticked. No AI tool sets a lock.
//   E-COP-090 - a kind of work not on the fixed list (map_building, planning, doing_work, research, general).
//   E-COP-091 - a new item when the account already holds max_active_items active ones (settings row, default 50).
//   E-COP-096 - a new item identical (title and body, case and spaces ignored) to an active one of the same kind and parent.
//
// Every change writes a FULL copy of the item to copilot_skill_version in the same transaction as
// the change. Unique (skill_id, version_no) is the race guard: two edits claiming the same number
// cannot both commit (a transaction alone does not serialize overlapping requests - CLAUDE.md).
// Only text / int / enum columns are patched here (never json), so a patch fully replaces.
function "copilot/skill_write" {
  input {
    int account_id
    int actor_user_id
    text changed_by? filters=trim
    text op? filters=trim
    int skill_id?
    text kind? filters=trim
    text title? filters=trim
    text body? filters=trim
    text condition_text? filters=trim
    int parent_skill_id?
    int link_to_skill_id?
    text scope_type? filters=trim
    int scope_ref_id?
    text scope_text? filters=trim
    text reason? filters=trim
    int copilot_run_id?
    int conversation_id?
    text work_kind? filters=trim
    bool let_ai_change?
  }

  stack {
    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    precondition ($input.op == "create" || $input.op == "edit" || $input.op == "retire") {
      error_type = "inputerror"
      error = "Choose create, edit or retire."
    }

    precondition ($input.changed_by == "copilot" || $input.changed_by == "owner") {
      error_type = "inputerror"
      error = "Say who is making the change: copilot or owner."
    }

    // ── The account's own copilot home (E-COP-086 if there is none) ──
    db.query copilot_home {
      where = $db.copilot_home.account_id == $input.account_id && $input.account_id != 0
      return = {type: "single"}
    } as $home

    var $home_arch {
      value = $home|get:"journey_architecture_id":0
    }

    db.query journey_architecture {
      where = $db.journey_architecture.id == $home_arch && $home_arch != 0
      return = {type: "single"}
      output = ["id", "owner_user", "account_id"]
    } as $home_row

    conditional {
      if ($home_arch == 0) {
        var.update $reject_code {
          value = "E-COP-086"
        }

        var.update $reject_msg {
          value = "The copilot has no business of its own yet, so it can't keep skills. An admin can set it up on Manage users. (E-COP-086)"
        }
      }
    }

    // ── The existing item, for edit and retire ──
    db.query copilot_skill {
      where = $db.copilot_skill.id == $input.skill_id && $input.skill_id != 0
      return = {type: "single"}
    } as $cur

    var $cur_id {
      value = $cur|get:"id":0
    }

    var $cur_ok {
      value = ($cur_id != 0 && ($cur|get:"account_id":0) == $input.account_id && ($cur|get:"home_architecture_id":0) == $home_arch)
    }

    var $cur_status {
      value = (($cur|get:"status":"") ?? "")
    }

    conditional {
      if ($reject_code == "" && $input.op != "create" && $cur_ok == false) {
        var.update $reject_code {
          value = "E-COP-081"
        }

        var.update $reject_msg {
          value = "The copilot can only write skills in its own business, 'how I work'. (E-COP-081)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.op != "create" && $cur_status == "retired") {
        var.update $reject_code {
          value = "E-COP-RETIRED"
        }

        var.update $reject_msg {
          value = "That skill is retired. The owner can bring it back with Undo."
        }
      }
    }

    // ── The values after the change (edit: an empty field keeps what is there) ──
    var $kind {
      value = (($input.op == "create") ? $input.kind : (($cur|get:"kind":"") ?? ""))
    }

    var $title {
      value = (($input.title != "") ? $input.title : (($cur|get:"title":"") ?? ""))
    }

    var $body {
      value = (($input.body != "") ? $input.body : (($cur|get:"body":"") ?? ""))
    }

    var $condition {
      value = (($input.condition_text != "") ? $input.condition_text : (($cur|get:"condition_text":"") ?? ""))
    }

    var $parent_id {
      value = (($input.parent_skill_id != 0) ? $input.parent_skill_id : (($cur|get:"parent_skill_id":0) ?? 0))
    }

    var $link_id {
      value = (($input.link_to_skill_id != 0) ? $input.link_to_skill_id : (($cur|get:"link_to_skill_id":0) ?? 0))
    }

    var $scope_type_in {
      value = (($input.scope_type != "") ? $input.scope_type : (($cur|get:"scope_type":"") ?? ""))
    }

    var $scope_type {
      value = (($scope_type_in != "") ? $scope_type_in : "all")
    }

    var $scope_ref {
      value = (($input.scope_ref_id != 0) ? $input.scope_ref_id : (($cur|get:"scope_ref_id":0) ?? 0))
    }

    var $scope_text {
      value = (($input.scope_text != "") ? $input.scope_text : (($cur|get:"scope_text":"") ?? ""))
    }

    var $title_len {
      value = $title|strlen
    }

    var $body_len {
      value = $body|strlen
    }

    var $cond_len {
      value = $condition|strlen
    }

    // ── Validation (create and edit; a retire only needs the item) ──
    conditional {
      if ($reject_code == "" && $input.op != "retire" && $kind != "skill" && $kind != "exception" && $kind != "lesson" && $kind != "link") {
        var.update $reject_code {
          value = "E-COP-KIND"
        }

        var.update $reject_msg {
          value = "Say what kind it is: skill, exception, lesson or link."
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.op != "retire" && ($title_len < 1 || $title_len > 120)) {
        var.update $reject_code {
          value = "E-COP-TITLE"
        }

        var.update $reject_msg {
          value = "Give it a short name (up to 120 characters)."
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.op != "retire" && ($body_len < 1 || $body_len > 4000 || $cond_len > 1000)) {
        var.update $reject_code {
          value = "E-COP-BODY"
        }

        var.update $reject_msg {
          value = "Write what to do (up to 4000 characters; a 'when' up to 1000)."
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.op != "retire" && $kind == "exception" && ($condition == "" || $parent_id == 0)) {
        var.update $reject_code {
          value = "E-COP-084"
        }

        var.update $reject_msg {
          value = "An exception needs a 'when'. Without one, this is a change to the skill. It also needs the skill it changes. (E-COP-084)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.op != "retire" && $kind == "link" && ($parent_id == 0 || $link_id == 0 || $parent_id == $link_id)) {
        var.update $reject_code {
          value = "E-COP-LINK"
        }

        var.update $reject_msg {
          value = "A link joins two different skills: the one it starts from and the one it points to."
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.op != "retire" && $scope_type != "all" && $scope_type != "business" && $scope_type != "map" && $scope_type != "work_kind") {
        var.update $reject_code {
          value = "E-COP-SCOPE"
        }

        var.update $reject_msg {
          value = "Say where it applies: all, business, map or work_kind."
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.op != "retire" && $scope_type == "work_kind" && $scope_text == "") {
        var.update $reject_code {
          value = "E-COP-SCOPE"
        }

        var.update $reject_msg {
          value = "Say which kind of work it applies to."
        }
      }
    }

    // ── Everything it points at must be inside the copilot's own business / this account ──
    db.query copilot_skill {
      where = $db.copilot_skill.id == $parent_id && $parent_id != 0
      return = {type: "single"}
    } as $parent

    var $parent_ok {
      value = ($parent_id == 0 || (($parent|get:"account_id":0) == $input.account_id && ($parent|get:"home_architecture_id":0) == $home_arch && ($parent|get:"kind":"") == "skill"))
    }

    db.query copilot_skill {
      where = $db.copilot_skill.id == $link_id && $link_id != 0
      return = {type: "single"}
    } as $linked

    var $link_ok {
      value = ($link_id == 0 || (($linked|get:"account_id":0) == $input.account_id && ($linked|get:"home_architecture_id":0) == $home_arch))
    }

    db.query journey_architecture {
      where = $db.journey_architecture.id == $scope_ref && $scope_type == "business" && $scope_ref != 0
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $scope_arch

    db.query journey_map {
      where = $db.journey_map.id == $scope_ref && $scope_type == "map" && $scope_ref != 0
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $scope_map

    var $scope_ok {
      value = ($scope_type == "all" || $scope_type == "work_kind" || ($scope_type == "business" && ($scope_arch|get:"account_id":0) == $input.account_id) || ($scope_type == "map" && ($scope_map|get:"account_id":0) == $input.account_id))
    }

    conditional {
      if ($reject_code == "" && $input.op != "retire" && ($parent_ok == false || $link_ok == false || $scope_ok == false)) {
        var.update $reject_code {
          value = "E-COP-081"
        }

        var.update $reject_msg {
          value = "The copilot can only write skills in its own business, 'how I work'. (E-COP-081)"
        }
      }
    }

    // ── COP-11: lock, kind of work, size limit, duplicates ──
    db.query copilot_skill_meta {
      where = $db.copilot_skill_meta.skill_id == $cur_id && $cur_id != 0
      return = {type: "single"}
    } as $meta

    var $meta_id {
      value = $meta|get:"id":0
    }

    var $is_locked {
      value = (($meta|get:"is_locked":false) == true)
    }

    var $cur_work_kind {
      value = (($meta|get:"work_kind":"") ?? "")
    }

    var $work_kind {
      value = (($input.work_kind != "") ? $input.work_kind : (($cur_work_kind != "") ? $cur_work_kind : "general"))
    }

    db.query copilot_library_setting {
      where = $db.copilot_library_setting.account_id == $input.account_id && $input.account_id != 0
      return = {type: "single"}
    } as $lib_setting

    var $max_items_raw {
      value = ($lib_setting|get:"max_active_items":0) ?? 0
    }

    var $max_items {
      value = (($max_items_raw != 0) ? $max_items_raw : 50)
    }

    db.query copilot_skill {
      where = $db.copilot_skill.account_id == $input.account_id && $input.account_id != 0 && $db.copilot_skill.status != "retired"
      return = {type: "count"}
    } as $active_count

    db.query copilot_skill {
      where = $db.copilot_skill.account_id == $input.account_id && $input.account_id != 0 && $db.copilot_skill.status != "retired"
      sort = {copilot_skill.updated_at: "asc"}
      return = {type: "list"}
      output = ["id", "title"]
    } as $active_list

    var $oldest {
      value = $active_list|first
    }

    var $oldest_id_text {
      value = (($oldest|get:"id":0)|to_text)
    }

    var $oldest_title {
      value = (($oldest|get:"title":"")|substr:0:60)
    }

    conditional {
      if ($reject_code == "" && $input.op != "create" && $input.changed_by == "copilot" && $is_locked) {
        var.update $reject_code {
          value = "E-COP-089"
        }

        var.update $reject_msg {
          value = "That item is locked by the owner. You can follow it but not change it: tell the owner what you would change and why, and let them edit it. (E-COP-089)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && $input.op != "retire" && $input.work_kind != "" && $input.work_kind != "map_building" && $input.work_kind != "planning" && $input.work_kind != "doing_work" && $input.work_kind != "research" && $input.work_kind != "general") {
        var.update $reject_code {
          value = "E-COP-090"
        }

        var.update $reject_msg {
          value = "Pick one of: map building, planning, doing work, research, general. (E-COP-090)"
        }
      }
    }

    var $active_text {
      value = $active_count|to_text
    }

    var $max_text {
      value = $max_items|to_text
    }

    conditional {
      if ($reject_code == "" && $input.op == "create" && $active_count >= $max_items) {
        var.update $reject_code {
          value = "E-COP-091"
        }

        var.update $reject_msg {
          value = "How I work is full (" ~ $active_text ~ " of " ~ $max_text ~ " items). Merge or retire an item first. Oldest: #" ~ $oldest_id_text ~ " " ~ $oldest_title ~ ". (E-COP-091)"
        }
      }
    }

    var $parent_cmp {
      value = ((($kind == "exception") || ($kind == "link")) ? $parent_id : 0)
    }

    db.query copilot_skill {
      where = $db.copilot_skill.account_id == $input.account_id && $input.account_id != 0 && $db.copilot_skill.status != "retired" && $db.copilot_skill.kind == $kind && $db.copilot_skill.parent_skill_id == $parent_cmp && $input.op == "create"
      return = {type: "list"}
      output = ["id", "title", "body"]
    } as $same_kind

    var $norm_title {
      value = $title|lower|replace:" ":""
    }

    var $norm_body {
      value = $body|lower|replace:" ":""
    }

    var $dup_id {
      value = 0
    }

    var $ct {
      value = ""
    }

    var $cb {
      value = ""
    }

    var $is_dup {
      value = false
    }

    foreach ($same_kind) {
      each as $c {
        var.update $ct {
          value = $c.title|lower|replace:" ":""
        }

        var.update $cb {
          value = $c.body|lower|replace:" ":""
        }

        var.update $is_dup {
          value = ($ct == $norm_title && $cb == $norm_body)
        }

        var.update $dup_id {
          value = ($is_dup ? $c.id : $dup_id)
        }
      }
    }

    var $dup_text {
      value = $dup_id|to_text
    }

    conditional {
      if ($reject_code == "" && $input.op == "create" && $dup_id != 0) {
        var.update $reject_code {
          value = "E-COP-096"
        }

        var.update $reject_msg {
          value = "That already exists in How I work as #" ~ $dup_text ~ ", so I didn't save it twice. Change that one instead if it needs different wording. (E-COP-096)"
        }
      }
    }

    // ── Story 03: the hard limits, on the server, before anything is stored ──
    function.run "copilot/skill_limits" {
      input = {
        title            : $title
        body             : $body
        condition_text   : $condition
        scope_text       : $scope_text
        reason           : $input.reason
        check_permissions: ($input.changed_by == "copilot")
      }
    } as $limits

    conditional {
      if ($reject_code == "" && $limits.code != "") {
        var.update $reject_code {
          value = $limits.code
        }

        var.update $reject_msg {
          value = $limits.message
        }
      }
    }

    // ── Refused: log, then raise. Nothing has been written. ──
    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-9"
            step       : "skill_" ~ $input.op
            outcome    : "rejected"
            severity   : "warn"
            error_code : $reject_code
            message    : $reject_msg
            user_id    : $input.actor_user_id
            account_id : $input.account_id
            entity_type: "copilot_skill"
            entity_id  : $cur_id
            metadata   : {changed_by: $input.changed_by, kind: $kind, copilot_run_id: $input.copilot_run_id, conversation_id: $input.conversation_id}
          }
        } as $_rejected_logged
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    // ── The write ──
    var $status {
      value = (($input.op == "create") ? "trial" : (($input.op == "retire") ? "retired" : $cur_status))
    }

    var $next_version {
      value = (($input.op == "create") ? 1 : ((($cur|get:"version_no":0) ?? 0) + 1))
    }

    var $scope_ref_final {
      value = ((($scope_type == "business") || ($scope_type == "map")) ? $scope_ref : 0)
    }

    var $condition_final {
      value = (($kind == "exception") ? $condition : "")
    }

    var $link_final {
      value = (($kind == "link") ? $link_id : 0)
    }

    var $parent_final {
      value = ((($kind == "exception") || ($kind == "link")) ? $parent_id : 0)
    }

    var $content {
      value = {}|set:"kind":$kind|set:"status":$status|set:"title":$title|set:"body":$body|set:"condition_text":$condition_final|set:"parent_skill_id":$parent_final|set:"link_to_skill_id":$link_final|set:"scope_type":$scope_type|set:"scope_ref_id":$scope_ref_final|set:"scope_text":$scope_text
    }

    var $owner_lock {
      value = ($input.changed_by == "owner" && $input.let_ai_change != true)
    }

    var $keep_lock {
      value = (($input.changed_by == "owner") ? false : $is_locked)
    }

    var $map_title {
      value = "Skill: " ~ $title
    }

    var $skill_id {
      value = $cur_id
    }

    var $map_id {
      value = ($cur|get:"journey_map_id":0) ?? 0
    }

    var $change {
      value = $input.op
    }

    var $write_ok {
      value = false
    }

    try_catch {
      try {
        db.transaction {
          stack {
            conditional {
              if ($input.op == "create") {
                db.add journey_map {
                  enforce_hidden_fields = false
                  data = {
                    created_at          : "now"
                    updated_at          : "now"
                    title               : $map_title
                    status              : "draft"
                    last_interaction_at : "now"
                    journey_architecture: $home_arch
                    account_id          : $input.account_id
                    owner_user          : ($home_row|get:"owner_user":0)
                    journey_scope       : $body
                  }
                } as $new_map

                db.add copilot_skill {
                  data = {
                    updated_at          : "now"
                    account_id          : $input.account_id
                    home_architecture_id: $home_arch
                    journey_map_id      : $new_map.id
                    kind                : $kind
                    status              : "trial"
                    title               : $title
                    body                : $body
                    condition_text      : $condition_final
                    parent_skill_id     : $parent_final
                    link_to_skill_id    : $link_final
                    scope_type          : $scope_type
                    scope_ref_id        : $scope_ref_final
                    scope_text          : $scope_text
                    version_no          : 1
                    created_by_user_id  : $input.actor_user_id
                    updated_by_user_id  : $input.actor_user_id
                  }
                } as $new_skill

                var.update $skill_id {
                  value = $new_skill.id
                }

                var.update $map_id {
                  value = $new_map.id
                }
              }

              else {
                db.patch copilot_skill {
                  field_name = "id"
                  field_value = $cur_id
                  data = {
                    updated_at        : "now"
                    status            : $status
                    title             : $title
                    body              : $body
                    condition_text    : $condition_final
                    parent_skill_id   : $parent_final
                    link_to_skill_id  : $link_final
                    scope_type        : $scope_type
                    scope_ref_id      : $scope_ref_final
                    scope_text        : $scope_text
                    version_no        : $next_version
                    updated_by_user_id: $input.actor_user_id
                  }
                } as $_patched

                conditional {
                  if ($map_id != 0) {
                    db.patch journey_map {
                      field_name = "id"
                      field_value = $map_id
                      data = {updated_at: "now", title: $map_title, journey_scope: $body}
                    } as $_map_patched
                  }
                }
              }
            }

            // COP-11: the lock and the kind of work (1:1 side table). The owner's own text is locked
            // unless let_ai_change is ticked (D-24-1); the copilot never sets or clears a lock.
            conditional {
              if ($input.op != "retire") {
                conditional {
                  if ($owner_lock) {
                    conditional {
                      if ($meta_id == 0) {
                        db.add copilot_skill_meta {
                          data = {updated_at: "now", skill_id: $skill_id, account_id: $input.account_id, is_locked: true, locked_by_user_id: $input.actor_user_id, locked_at: "now", work_kind: $work_kind}
                        } as $_meta_added
                      }

                      else {
                        db.patch copilot_skill_meta {
                          field_name = "id"
                          field_value = $meta_id
                          data = {updated_at: "now", is_locked: true, locked_by_user_id: $input.actor_user_id, locked_at: "now", work_kind: $work_kind}
                        } as $_meta_patched
                      }
                    }
                  }

                  else {
                    conditional {
                      if ($meta_id == 0) {
                        db.add copilot_skill_meta {
                          data = {updated_at: "now", skill_id: $skill_id, account_id: $input.account_id, is_locked: false, work_kind: $work_kind}
                        } as $_meta_added2
                      }

                      else {
                        db.patch copilot_skill_meta {
                          field_name = "id"
                          field_value = $meta_id
                          data = {updated_at: "now", is_locked: $keep_lock, work_kind: $work_kind}
                        } as $_meta_patched2
                      }
                    }
                  }
                }
              }
            }

            db.add copilot_skill_version {
              data = {
                skill_id          : $skill_id
                account_id        : $input.account_id
                version_no        : $next_version
                change            : $change
                changed_by        : $input.changed_by
                changed_by_user_id: $input.actor_user_id
                reason            : $input.reason
                content           : $content
                copilot_run_id    : $input.copilot_run_id
                conversation_id   : $input.conversation_id
                undo_of_version_no: 0
              }
            } as $_version

            var.update $write_ok {
              value = true
            }
          }
        }
      }

      catch {
        var.update $write_ok {
          value = false
        }
      }
    }

    conditional {
      if ($write_ok == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-9"
            step       : "skill_" ~ $input.op
            outcome    : "failure"
            severity   : "warn"
            error_code : ""
            message    : "A skill change could not be saved; nothing was changed."
            user_id    : $input.actor_user_id
            account_id : $input.account_id
            entity_type: "copilot_skill"
            entity_id  : $cur_id
            metadata   : {changed_by: $input.changed_by, version_no: $next_version}
          }
        } as $_failed_logged
      }
    }

    precondition ($write_ok == true) {
      error_type = "inputerror"
      error = "That skill was changed by someone else at the same moment, or couldn't be saved. Nothing was changed; read it again and retry."
    }

    function.run "ops/log_event" {
      input = {
        feature    : "COP-9"
        step       : "skill_" ~ $input.op
        outcome    : "success"
        severity   : "info"
        error_code : ""
        message    : "A skill in 'how I work' was saved."
        user_id    : $input.actor_user_id
        account_id : $input.account_id
        entity_type: "copilot_skill"
        entity_id  : $skill_id
        metadata   : {changed_by: $input.changed_by, kind: $kind, status: $status, version_no: $next_version, copilot_run_id: $input.copilot_run_id, conversation_id: $input.conversation_id}
      }
    } as $_ok_logged
  }

  response = {skill_id: $skill_id, version_no: $next_version, status: $status, kind: $kind, journey_map_id: $map_id}
}
