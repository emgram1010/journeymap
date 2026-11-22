// AIM-1 story 03 — find the AI member behind an access token. Only the SHA-256 hash is ever compared; the token is never stored, logged or returned. A token is good when its row exists, is not revoked and has not expired. A good lookup stamps last_used_at. Never throws: returns user_id 0 with a reason (bad_token, revoked_token, expired_token).
function "aim/token_lookup" {
  input {
    text token? filters=trim
  }

  stack {
    var $hash {
      value = ($input.token ?? "")|sha256
    }

    db.query agent_access_token {
      where = $db.agent_access_token.token_hash == $hash && $input.token != ""
      return = {type: "single"}
    } as $row

    var $token_id {
      value = $row|get:"id":0
    }

    var $revoked {
      value = (($row|get:"revoked_at":0) ?? 0)|to_int
    }

    var $expires {
      value = (($row|get:"expires_at":0) ?? 0)|to_int
    }

    var $now_ms {
      value = now|to_int
    }

    var $user_id {
      value = 0
    }

    var $reason {
      value = "bad_token"
    }

    conditional {
      if ($token_id != 0 && $revoked != 0) {
        var.update $reason {
          value = "revoked_token"
        }
      }

      elseif ($token_id != 0 && $expires <= $now_ms) {
        var.update $reason {
          value = "expired_token"
        }
      }

      elseif ($token_id != 0) {
        var.update $reason {
          value = "ok"
        }

        var.update $user_id {
          value = $row|get:"user_id":0
        }

        db.patch agent_access_token {
          field_name = "id"
          field_value = $token_id
          data = {last_used_at: "now"}
        } as $_used
      }
    }

    var $out_token_id {
      value = 0
    }

    conditional {
      if ($reason == "ok") {
        var.update $out_token_id {
          value = $token_id
        }
      }
    }
  }

  response = {user_id: $user_id, token_id: $out_token_id, reason: $reason}
}
