// SAFE-1 story 03 (2026-11-21) — an admin makes (or cancels) a one-time "set a new password" link
// for someone in their account. No email is sent (D-8): the token comes back ONCE in this response,
// the app shows the link once, and the admin hands it over. The admin never sees or sets a password.
//
// Who may reset whom (D-9, D-10), asked of usr/account_rank, never copied here:
//   an admin resets a member; only the account owner resets another admin; nobody in the account
//   resets the owner (E-SAFE-007); nobody resets themself here (E-SAFE-009); an AI login is never
//   reset (E-SAFE-010) because a password for it would let a person act as the AI outside the tool gate.
// Also refused: a switched-off person (E-SAFE-004); a person whose email an admin changed in the
// last 24 hours (E-SAFE-005, the change-email-then-reset takeover); a sixth link by one admin in an
// hour (E-SAFE-002, counted on event_log because redis is not available on this plan).
// Another account's person answers "not found" (E-USR-002), the same as nobody.
//
// The link is the existing 1-hour, single-use magic link (D-1); making a new one retires the old
// one. cancel = true retires the current link without making a new one.
// The token is NEVER written to event_log. Every refusal is logged before it is raised.
query "admin/user_reset_link" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // Optional so a missing id answers "not found" in this endpoint's own words.
    int user_id?

    // true = retire the person's current link; no new link is made.
    bool cancel?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id : $auth.id
        step          : "admin/user_reset_link"
        entity_id     : $input.user_id
        correlation_id: ""
      }
    } as $admin

    db.query user {
      where = $db.user.id == $input.user_id
      return = {type: "single"}
      output = ["id", "name", "email", "account_id"]
    } as $t

    var $tid {
      value = $t|get:"id":0
    }

    var $tacct {
      value = $t|get:"account_id":0
    }

    var $temail {
      value = $t|get:"email":""
    }

    // Real ids start at 1; 0 means no such person. Same answer for another account's person.
    var $in_my_account {
      value = ($tid > 0 && $tacct == $admin.account_id)
    }

    precondition ($in_my_account) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    function.run "usr/account_rank" {
      input = {user_id: $tid}
    } as $tr

    function.run "usr/account_rank" {
      input = {user_id: $admin.id}
    } as $ar

    var $making {
      value = ($input.cancel == false)
    }

    db.query user_status {
      where = $db.user_status.user_id == $tid
      return = {type: "single"}
      output = ["id", "is_active"]
    } as $status_row

    var $is_active {
      value = $status_row|get:"is_active":true
    }

    var $now_ms {
      value = now|to_int
    }

    var $cut_24h {
      value = $now_ms - 86400000
    }

    var $cut_1h {
      value = $now_ms - 3600000
    }

    // Did an admin change this person's email in the last 24 hours? admin/user_update logs
    // which fields changed (never the values) with the target's id.
    db.query event_log {
      where = $db.event_log.action == "updated_user_profile" && $db.event_log.account_id == $admin.account_id && $db.event_log.created_at >= $cut_24h
      return = {type: "list"}
      output = ["id", "metadata"]
    } as $profile_events

    var $email_hits {
      value = 0
    }

    foreach ($profile_events) {
      each as $e {
        var $hit_t {
          value = (($e.metadata|get:"target_user_id":0) == $tid)
        }

        var $hit_e {
          value = (($e.metadata|get:"email_changed":false) == true)
        }

        var.update $email_hits {
          value = $email_hits + (($hit_t && $hit_e)|to_int)
        }
      }
    }

    db.query event_log {
      where = $db.event_log.feature == "SAFE-1" && $db.event_log.step == "admin/user_reset_link" && $db.event_log.outcome == "success" && $db.event_log.user_id == $admin.id && $db.event_log.created_at >= $cut_1h
      return = {type: "count"}
    } as $recent_links

    // One verdict, first match wins. Not inside a loop, so reading these vars is safe.
    var $code {
      value = ""
    }

    conditional {
      if ($admin.id == $tid) {
        var.update $code {
          value = "E-SAFE-009"
        }
      }

      elseif ($tr.is_ai == true) {
        var.update $code {
          value = "E-SAFE-010"
        }
      }

      elseif ($tr.is_owner == true) {
        var.update $code {
          value = "E-SAFE-007"
        }
      }

      elseif ($tr.is_admin == true && $ar.is_owner == false) {
        var.update $code {
          value = "E-SAFE-006"
        }
      }

      elseif ($making && $is_active != true) {
        var.update $code {
          value = "E-SAFE-004"
        }
      }

      elseif ($making && $email_hits > 0) {
        var.update $code {
          value = "E-SAFE-005"
        }
      }

      elseif ($making && $recent_links >= 5) {
        var.update $code {
          value = "E-SAFE-002"
        }
      }
    }

    conditional {
      if ($code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "SAFE-1"
            step          : "admin/user_reset_link"
            outcome       : "rejected"
            severity      : "warn"
            error_code    : $code
            message       : "Refused: a password reset link was not made."
            user_id       : $admin.id
            account_id    : $admin.account_id
            entity_type   : "user"
            entity_id     : $tid
            correlation_id: ""
            duration_ms   : 0
            metadata      : {actor_rank: $ar.rank, target_rank: $tr.rank, cancel: $input.cancel}
          }
        } as $_denied
      }
    }

    precondition ($code != "E-SAFE-009") {
      error_type = "accessdenied"
      error = "To change your own password, use your own profile. (E-SAFE-009)"
    }

    precondition ($code != "E-SAFE-010") {
      error_type = "accessdenied"
      error = "AI members don't use passwords. Re-issue its access token instead. (E-SAFE-010)"
    }

    precondition ($code != "E-SAFE-007") {
      error_type = "accessdenied"
      error = "The account owner can't be reset here. Contact Emgram support. (E-SAFE-007)"
    }

    precondition ($code != "E-SAFE-006") {
      error_type = "accessdenied"
      error = "Only the account owner can reset another admin. (E-SAFE-006)"
    }

    precondition ($code != "E-SAFE-004") {
      error_type = "accessdenied"
      error = "This person is switched off. Switch them back on first. (E-SAFE-004)"
    }

    precondition ($code != "E-SAFE-005") {
      error_type = "accessdenied"
      error = "This person's email was changed in the last 24 hours, so a reset has to wait. (E-SAFE-005)"
    }

    precondition ($code != "E-SAFE-002") {
      error_type = "accessdenied"
      error = "You've made several reset links in the last hour. Try again later. (E-SAFE-002)"
    }

    var $token {
      value = ""
    }

    conditional {
      if ($making) {
        function.run "Getting Started Template/generate_magic_link" {
          input = {email: $temail}
        } as $link

        var.update $token {
          value = $link.token
        }
      }

      else {
        // Retire the current link: an unknown random token, already used, already expired.
        security.create_uuid as $dead

        db.edit user {
          field_name = "id"
          field_value = $tid
          enforce_hidden_fields = false
          data = {password_reset: {token: $dead, expiration: $now_ms, used: true}}
        } as $_retired
      }
    }

    var $done_step {
      value = ($making ? "reset_link_made" : "reset_link_cancelled")
    }

    // Who, for whom, when. Never the token.
    function.run "ops/log_event" {
      input = {
        feature       : "SAFE-1"
        step          : "admin/user_reset_link"
        outcome       : "success"
        severity      : "info"
        error_code    : ""
        message       : "A password reset link was made or cancelled for a person in the account."
        user_id       : $admin.id
        account_id    : $admin.account_id
        entity_type   : "user"
        entity_id     : $tid
        correlation_id: ""
        duration_ms   : 0
        metadata      : {kind: $done_step, actor_rank: $ar.rank, target_rank: $tr.rank}
      }
    } as $_logged
  }

  response = {user_id: $tid, email: $temail, cancelled: ($making == false), token: $token, expires_in_minutes: 60}
  tags = ["safe-1"]
}
