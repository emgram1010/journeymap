// JOB-1 (US-JOB-1-04) — Set one attribute on a job.
//
// EVERY ATTRIBUTE RECORDS WHERE IT CAME FROM AND WHEN, stored as
// {value, source, entered_at}. Today the only source is `manual`,
// but an intake form, an email parser or an AI extraction will each
// want to say so, and a plain `{key: value}` map could not without a
// migration.
//
// ⚠️ THE EVENT LOGS THE KEY NAME ONLY, NEVER THE VALUE. Attributes
// are free text supplied by the planner, so they are exactly where a
// customer name, an address or a price will end up. OBS-1's log is
// read by support and copied into diagnostic bundles; values must not
// travel with it. The epic calls this out explicitly and it is easy
// to get wrong by logging the whole object "for debugging".
// Verified live: setting `customer_name = "Acme Ltd"` logged
// `{attribute_key: "customer_name", source: "manual"}` and no value.
//
// Values are short text or a number, never a nested object: the MVP
// is deliberately a flat key/value bag (D-44), and nesting would make
// the later intake schema harder to introduce, not easier.
query "work_item/{work_item_id}/attribute" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int work_item_id filters=min:1
    text key filters=trim
    text value filters=trim
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.get work_item {
      field_name = "id"
      field_value = $input.work_item_id
    } as $job

    var $belongs {
      value = ($job != null && $job.account_id == $actor.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Job not found"
    }

    var $existing {
      value = ($job.attributes ?? {})
    }

    var $key_count {
      value = ($existing|keys)|count
    }

    var $already_has {
      value = $existing|get:$input.key:null
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($input.key == "" || ($input.key|strlen) > 40 || ("/^[A-Za-z0-9_]+$/"|regex_matches:$input.key) == false) {
        var.update $reject_code {
          value = "E-JOB-004"
        }

        var.update $reject_msg {
          value = "That detail isn't valid. Use short text or a number. (E-JOB-004)"
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($input.value|strlen) > 200) {
        var.update $reject_code {
          value = "E-JOB-004"
        }

        var.update $reject_msg {
          value = "That detail isn't valid. Use short text or a number. (E-JOB-004)"
        }
      }
    }

    // 50 keys is the cap, but replacing an existing key is always fine
    // even at the cap — otherwise a full job could never be corrected.
    conditional {
      if ($reject_code == "" && $key_count >= 50 && $already_has == null) {
        var.update $reject_code {
          value = "E-JOB-004"
        }

        var.update $reject_msg {
          value = "That detail isn't valid. Use short text or a number. (E-JOB-004)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "JOB-1"
            step          : "set_attribute"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "work_item"
            entity_id     : $input.work_item_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Attribute refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $now_ms {
      value = now|to_int
    }

    var $entry {
      value = {value: $input.value, source: "manual", entered_at: $now_ms}
    }

    var $next_attributes {
      value = $existing|set:$input.key:$entry
    }

    db.patch work_item {
      field_name = "id"
      field_value = $input.work_item_id
      data = {attributes: $next_attributes, updated_at: "now"}
    } as $updated

    // Key name only. Never the value.
    function.run "ops/log_event" {
      input = {
        feature       : "JOB-1"
        step          : "set_attribute"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "work_item"
        entity_id     : $input.work_item_id
        correlation_id: $input.correlation_id
        message       : "Job attribute set."
        metadata      : {attribute_key: $input.key, source: "manual"}
      }
    }
  }

  response = {
    work_item_id: $input.work_item_id
    attributes  : $updated.attributes
  }
}
