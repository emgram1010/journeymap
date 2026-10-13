// VAL-1 (demonstrates US-VAL-1-01…05 live) + GOV-1 (US-GOV-1-12) —
// Admin-only write for account_feature_flag. The smoke test during
// GOV-1 wrote the table directly (addTableContent); this is the real,
// validated endpoint that replaces that workaround.
//
// Upserts on (account_id, flag_key), matching the table's unique index.
// db.edit/db.add_or_edit only match on a SINGLE field in this
// XanoScript version, so the composite match is done by hand: query
// for an existing row, then edit by id or add.
query "ops/feature_flag" verb=POST {
  api_group = "Ops"
  auth = "user"

  input {
    int account_id
    text flag_key filters=trim
    bool enabled
    text note? filters=trim
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    function.run "validate_field" {
      input = {
        raw          : $input.flag_key
        type         : "enum"
        required     : true
        label        : "Flag"
        allowed_values: ["required_fields_ui", "publish_gate"]
        required_code: "E-VAL-001"
        not_allowed_code: "E-VAL-004"
      }
    } as $flag_key_check

    conditional {
      if ($flag_key_check.ok == false) {
        function.run "ops/log_event" {
          input = {
            feature   : "VAL-1"
            step      : "feature_flag_set"
            outcome   : "rejected"
            severity  : "info"
            error_code: $flag_key_check.code
            message   : $flag_key_check.message
            account_id: $input.account_id
          }
        } as $_logged_bad_key
      }
    }

    precondition ($flag_key_check.ok) {
      error_type = "inputerror"
      error = $flag_key_check.message ~ " (" ~ $flag_key_check.code ~ ")"
    }

    function.run "validate_field" {
      input = {
        raw          : $input.note
        type         : "text"
        required     : false
        label        : "Note"
        has_max_length: true
        max_length   : 500
        no_html      : true
        too_long_code: "E-VAL-002"
        html_code    : "E-VAL-005"
      }
    } as $note_check

    conditional {
      if ($note_check.ok == false) {
        function.run "ops/log_event" {
          input = {
            feature   : "VAL-1"
            step      : "feature_flag_set"
            outcome   : "rejected"
            severity  : "info"
            error_code: $note_check.code
            message   : $note_check.message
            account_id: $input.account_id
          }
        } as $_logged_bad_note
      }
    }

    precondition ($note_check.ok) {
      error_type = "inputerror"
      error = $note_check.message ~ " (" ~ $note_check.code ~ ")"
    }

    function.run "validate_field" {
      input = {
        raw          : ($input.account_id|to_text)
        type         : "int"
        required     : true
        label        : "Account"
        has_min_value: true
        min_value    : 1
        required_code: "E-VAL-001"
        out_of_range_code: "E-VAL-003"
      }
    } as $account_id_check

    precondition ($account_id_check.ok) {
      error_type = "inputerror"
      error = $account_id_check.message ~ " (" ~ $account_id_check.code ~ ")"
    }

    db.query account {
      where = $db.account.id == $input.account_id
      return = {type: "list"}
    } as $account_rows

    var $account_count {
      value = $account_rows|count
    }

    conditional {
      if ($account_count == 0) {
        function.run "ops/log_event" {
          input = {
            feature   : "VAL-1"
            step      : "feature_flag_set"
            outcome   : "rejected"
            severity  : "info"
            error_code: "E-VAL-007"
            message   : "That account couldn't be found."
            account_id: $input.account_id
          }
        } as $_logged_bad_account
      }
    }

    precondition ($account_count > 0) {
      error_type = "inputerror"
      error = "That account couldn't be found. (E-VAL-007)"
    }

    db.query account_feature_flag {
      where = $db.account_feature_flag.account_id == $input.account_id && $db.account_feature_flag.flag_key == $input.flag_key
      return = {type: "list"}
    } as $existing_rows

    // Avoid [0] indexing (unproven on real data in this workspace — see
    // CLAUDE.md); find the single match, if any, with a loop instead.
    var $existing_id {
      value = null
    }

    foreach ($existing_rows) {
      each as $row {
        conditional {
          if ($existing_id == null) {
            var.update $existing_id {
              value = $row.id
            }
          }
        }
      }
    }

    var $saved {
      value = null
    }

    conditional {
      if ($existing_id != null) {
        db.edit account_feature_flag {
          field_name = "id"
          field_value = $existing_id
          data = {
            enabled   : $input.enabled
            note      : $input.note
            updated_at: "now"
          }
        } as $edited_row

        var.update $saved {
          value = $edited_row
        }
      }

      else {
        db.add account_feature_flag {
          data = {
            account_id: $input.account_id
            flag_key  : $input.flag_key
            enabled   : $input.enabled
            note      : $input.note
          }
        } as $added_row

        var.update $saved {
          value = $added_row
        }
      }
    }

    function.run "ops/log_event" {
      input = {
        feature   : "VAL-1"
        step      : "feature_flag_set"
        outcome   : "success"
        severity  : "info"
        account_id: $input.account_id
        entity_type: "account_feature_flag"
        entity_id : $saved.id
      }
    } as $_logged
  }

  response = $saved
}
