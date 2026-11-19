// COP-13 story 05 (Health part) — the "Stronger model" panel: for the last 7 days, per UTC day and
// per business, how many times the copilot asked to use the stronger model and what happened.
//   requested / capped / granted / ran come from event_log (copilot.step_up.*; ran = success only);
//   approved / declined / expired / waiting come from the approval items (copilot_action,
//   action_type step_up_model): approved also counts edited, executed and failed (the owner said yes).
// Business: event rows name the conversation, so the conversations are looked up with ONE query
// constrained to their ids (no `if` inside a loop); approval items carry the business themselves.
// Counting uses (flag)|to_int, never a conditional inside a foreach. Keys use "::", never a pipe.
// Read-only. Platform admins only, through ops/step_ups.
function "ops/step_ups_panel" {
  input {
  }

  stack {
    var $days {
      value = 7
    }

    var $now_ms {
      value = now|to_int
    }

    var $since {
      value = $now_ms - ($days * 86400000)
    }

    var $steps {
      value = ["copilot.step_up.requested", "copilot.step_up.capped", "copilot.step_up.granted", "copilot.step_up.ran"]
    }

    db.query event_log {
      where = $db.event_log.step in $steps && $db.event_log.created_at >= $since
      return = {type: "list"}
      output = ["step", "outcome", "entity_id", "created_at"]
    } as $events

    var $conv_ids {
      value = [-1]
    }

    foreach ($events) {
      each as $e {
        array.push $conv_ids {
          value = $e.entity_id
        }
      }
    }

    db.query agent_conversation {
      where = $db.agent_conversation.id in $conv_ids
      return = {type: "list"}
      output = ["id", "journey_architecture_id"]
    } as $convs

    var $conv_arch {
      value = {}
    }

    var $ck {
      value = ""
    }

    foreach ($convs) {
      each as $c {
        var.update $ck {
          value = "c::" ~ ($c.id|to_text)
        }

        var.update $conv_arch {
          value = $conv_arch|set:$ck:$c.journey_architecture_id
        }
      }
    }

    db.query copilot_action {
      where = $db.copilot_action.action_type == "step_up_model" && $db.copilot_action.created_at >= $since
      return = {type: "list"}
      output = ["status", "journey_architecture_id", "created_at"]
    } as $acts

    // One counter map per measure, keyed "k::<day>::<business>"; $meta holds {day, business} per key.
    var $req {
      value = {}
    }

    var $cap {
      value = {}
    }

    var $grant {
      value = {}
    }

    var $ran {
      value = {}
    }

    var $appr {
      value = {}
    }

    var $decl {
      value = {}
    }

    var $expd {
      value = {}
    }

    var $wait {
      value = {}
    }

    var $meta {
      value = {}
    }

    var $k {
      value = ""
    }

    var $day {
      value = 0
    }

    var $arch {
      value = 0
    }

    var $n {
      value = 0
    }

    var $ek {
      value = ""
    }

    var $cell {
      value = {}
    }

    foreach ($events) {
      each as $e {
        var.update $day {
          value = ($e.created_at / 86400000)|to_int
        }

        var.update $ek {
          value = "c::" ~ ($e.entity_id|to_text)
        }

        var.update $arch {
          value = ($conv_arch|get:$ek:null) ?? 0
        }

        var.update $k {
          value = "k::" ~ ($day|to_text) ~ "::" ~ ($arch|to_text)
        }

        var.update $cell {
          value = {day: $day, journey_architecture_id: $arch}
        }

        var.update $meta {
          value = $meta|set:$k:$cell
        }

        var.update $n {
          value = (($req|get:$k:null) ?? 0) + (($e.step == "copilot.step_up.requested")|to_int)
        }

        var.update $req {
          value = $req|set:$k:$n
        }

        var.update $n {
          value = (($cap|get:$k:null) ?? 0) + (($e.step == "copilot.step_up.capped")|to_int)
        }

        var.update $cap {
          value = $cap|set:$k:$n
        }

        var.update $n {
          value = (($grant|get:$k:null) ?? 0) + (($e.step == "copilot.step_up.granted")|to_int)
        }

        var.update $grant {
          value = $grant|set:$k:$n
        }

        var.update $n {
          value = (($ran|get:$k:null) ?? 0) + (($e.step == "copilot.step_up.ran" && $e.outcome == "success")|to_int)
        }

        var.update $ran {
          value = $ran|set:$k:$n
        }
      }
    }

    foreach ($acts) {
      each as $a {
        var.update $day {
          value = ($a.created_at / 86400000)|to_int
        }

        var.update $arch {
          value = $a.journey_architecture_id ?? 0
        }

        var.update $k {
          value = "k::" ~ ($day|to_text) ~ "::" ~ ($arch|to_text)
        }

        var.update $cell {
          value = {day: $day, journey_architecture_id: $arch}
        }

        var.update $meta {
          value = $meta|set:$k:$cell
        }

        var.update $n {
          value = (($appr|get:$k:null) ?? 0) + (($a.status == "approved" || $a.status == "edited" || $a.status == "executed" || $a.status == "failed")|to_int)
        }

        var.update $appr {
          value = $appr|set:$k:$n
        }

        var.update $n {
          value = (($decl|get:$k:null) ?? 0) + (($a.status == "rejected")|to_int)
        }

        var.update $decl {
          value = $decl|set:$k:$n
        }

        var.update $n {
          value = (($expd|get:$k:null) ?? 0) + (($a.status == "expired")|to_int)
        }

        var.update $expd {
          value = $expd|set:$k:$n
        }

        var.update $n {
          value = (($wait|get:$k:null) ?? 0) + (($a.status == "waiting")|to_int)
        }

        var.update $wait {
          value = $wait|set:$k:$n
        }
      }
    }

    // Business names, with one query constrained to the businesses that appear.
    var $arch_ids {
      value = [-1]
    }

    var $metas {
      value = $meta|values
    }

    foreach ($metas) {
      each as $m {
        array.push $arch_ids {
          value = $m.journey_architecture_id
        }
      }
    }

    db.query journey_architecture {
      where = $db.journey_architecture.id in $arch_ids
      return = {type: "list"}
      output = ["id", "title"]
    } as $archs

    var $names {
      value = {}
    }

    var $nk {
      value = ""
    }

    foreach ($archs) {
      each as $ar {
        var.update $nk {
          value = "a::" ~ ($ar.id|to_text)
        }

        var.update $names {
          value = $names|set:$nk:$ar.title
        }
      }
    }

    var $keys {
      value = $meta|keys
    }

    var $rows {
      value = []
    }

    var $mrow {
      value = {}
    }

    var $r_day {
      value = 0
    }

    var $r_arch {
      value = 0
    }

    var $r_name {
      value = ""
    }

    var $r_req {
      value = 0
    }

    var $r_cap {
      value = 0
    }

    var $r_grant {
      value = 0
    }

    var $r_ran {
      value = 0
    }

    var $r_appr {
      value = 0
    }

    var $r_decl {
      value = 0
    }

    var $r_exp {
      value = 0
    }

    var $r_wait {
      value = 0
    }

    foreach ($keys) {
      each as $key {
        var.update $mrow {
          value = $meta|get:$key:null
        }

        var.update $r_day {
          value = $mrow.day ?? 0
        }

        var.update $r_arch {
          value = $mrow.journey_architecture_id ?? 0
        }

        var.update $nk {
          value = "a::" ~ ($r_arch|to_text)
        }

        var.update $r_name {
          value = ($names|get:$nk:null) ?? ""
        }

        var.update $r_req {
          value = ($req|get:$key:null) ?? 0
        }

        var.update $r_cap {
          value = ($cap|get:$key:null) ?? 0
        }

        var.update $r_grant {
          value = ($grant|get:$key:null) ?? 0
        }

        var.update $r_ran {
          value = ($ran|get:$key:null) ?? 0
        }

        var.update $r_appr {
          value = ($appr|get:$key:null) ?? 0
        }

        var.update $r_decl {
          value = ($decl|get:$key:null) ?? 0
        }

        var.update $r_exp {
          value = ($expd|get:$key:null) ?? 0
        }

        var.update $r_wait {
          value = ($wait|get:$key:null) ?? 0
        }

        array.push $rows {
          value = {day: $r_day, journey_architecture_id: $r_arch, business: $r_name, requested: $r_req, capped: $r_cap, granted: $r_grant, ran: $r_ran, approved: $r_appr, declined: $r_decl, expired: $r_exp, waiting: $r_wait}
        }
      }
    }
  }

  response = {days: $days, rows: $rows}
}
