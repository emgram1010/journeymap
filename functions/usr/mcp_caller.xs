// SEC-3 (US-SEC-3-01..03) — who is knocking on the AI tool address, and may they come in?
//
// Called by the MCP server's "Auth Gate" trigger on every connection. The trigger has no
// `$auth` of its own (proven live 2026-11-14: `$auth.id` and `$input.auth` are both empty even
// with a valid Bearer token), but it CAN see the request headers and the request address. So
// the token is read from there and checked by asking our own `auth/whoami` endpoint, which is
// the platform's token check and nothing else.
//
// Then the SAME rule a person meets on the screen: `usr/assert_module_access` for the
// Intelligent Layer (switched on + granted). No second copy of that rule.
//
// FAILS CLOSED: no token, a bad token, a refused module check or any error all return
// `allowed: false`. It never throws, so the trigger can always answer "no tools".
//
// The token may arrive as an `Authorization: Bearer …` header (preferred) or as `?token=…` on
// the address, because some outside assistants can only be given an address. A token in an
// address can end up in logs on the caller's side — the header is safer where it is possible.
//
// Passes are not logged (this runs on every connection). A refused module check is logged by
// `usr/assert_module_access` itself. A missing or bad token is logged at most 5 times per
// reason per hour (US-SEC-3-05), so a public address cannot flood the log.
function "usr/mcp_caller" {
  input {
    // The raw Authorization header, or "" when there is none.
    text authorization?

    // The request address including its query string, or "".
    text uri?
  }

  stack {
    var $token {
      value = ""
    }

    var $has_bearer {
      value = "/^Bearer [^ ]+/i"|regex_matches:$input.authorization
    }

    var $has_query_token {
      value = "/[?&]token=[^&]+/"|regex_matches:$input.uri
    }

    conditional {
      if ($has_bearer) {
        var.update $token {
          value = "/^Bearer +/i"|regex_replace:"":$input.authorization
        }
      }

      elseif ($has_query_token) {
        var.update $token {
          value = "/^.*[?&]token=([^&]+).*$/"|regex_replace:"$1":$input.uri
        }
      }
    }

    var.update $token {
      value = $token|trim
    }

    var $user_id {
      value = 0
    }

    var $reason {
      value = "no_token"
    }

    var $allowed {
      value = false
    }

    // AIM-1 story 03: an AI member's own access token (emg_ai_ + 64 hex). Looked up by hash in
    // aim/token_lookup; never sent to auth/whoami, never logged.
    var $is_agent_token {
      value = "/^emg_ai_[a-f0-9]{64}$/"|regex_matches:$token
    }

    var $agent_token_id {
      value = 0
    }

    conditional {
      if ($is_agent_token) {
        function.run "aim/token_lookup" {
          input = {token: $token}
        } as $agent_lookup

        var.update $user_id {
          value = $agent_lookup.user_id
        }

        var.update $agent_token_id {
          value = $agent_lookup.token_id
        }

        var.update $reason {
          value = $agent_lookup.reason
        }
      }
    }

    conditional {
      if ($token != "" && $is_agent_token == false) {
        var.update $reason {
          value = "bad_token"
        }

        try_catch {
          try {
            var $auth_header {
              value = "Authorization: Bearer " ~ $token
            }

            api.request {
              url = "https://xdjc-i7zz-jhm2.n7e.xano.io/api:RPonubWS/auth/whoami"
              method = "GET"
              params = {}
              headers = []|push:$auth_header
              timeout = 10
            } as $resp

            var $status {
              value = $resp.response.status ?? 0
            }

            var $body {
              value = $resp.response.result ?? {}
            }

            var $found_id {
              value = $body|get:"id":0
            }

            conditional {
              if ($status == 200 && $found_id != 0) {
                var.update $user_id {
                  value = $found_id
                }
              }
            }
          }

          catch {
            var.update $reason {
              value = "check_failed"
            }
          }
        }
      }
    }

    // AIM-1 (threat T-7): an AI member comes in with its own access token only. A person-style
    // sign-in for an AI member's login is refused here, so revoking its token really stops it.
    conditional {
      if ($user_id != 0 && $is_agent_token == false) {
        db.query ai_member_profile {
          where = $db.ai_member_profile.user_id == $user_id
          return = {type: "count"}
        } as $ai_login_rows

        conditional {
          if ($ai_login_rows > 0) {
            var.update $user_id {
              value = 0
            }

            var.update $reason {
              value = "bad_token"
            }
          }
        }
      }
    }

    conditional {
      if ($user_id != 0) {
        var.update $reason {
          value = "not_allowed"
        }

        try_catch {
          try {
            function.run "usr/assert_module_access" {
              input = {
                actor_user_id: $user_id
                module       : "intelligence"
                step         : "mcp/connect"
                or_module    : ""
              }
            } as $_ok

            var.update $allowed {
              value = true
            }

            var.update $reason {
              value = "ok"
            }
          }

          catch {
            var.update $allowed {
              value = false
            }
          }
        }
      }
    }

    // US-SEC-3-05 (2026-11-16): a refusal for no token, a bad token or a failed check is logged
    // so Health shows it (E-SEC-020, reason in metadata) - but at most 5 rows per reason per hour,
    // so a public address hammered with no token cannot flood event_log. Counted with a plain
    // db.query count against a cutoff var (no redis on this plan; OBS-1 pattern). Never logs the
    // token, the header or the address. "not_allowed" is already logged by usr/assert_module_access.
    var $log_refusal {
      value = ($reason == "no_token") || ($reason == "bad_token") || ($reason == "check_failed") || ($reason == "revoked_token") || ($reason == "expired_token")
    }

    conditional {
      if ($log_refusal == true) {
        try_catch {
          try {
            var $now_ms {
              value = now|to_int
            }

            var $cutoff {
              value = $now_ms - 3600000
            }

            var $step_name {
              value = "mcp_connect_refused_" ~ $reason
            }

            db.query event_log {
              where = $db.event_log.feature == "SEC-3" && $db.event_log.step == $step_name && $db.event_log.created_at >= $cutoff
              return = {type: "count"}
            } as $recent

            conditional {
              if ($recent < 5) {
                function.run "ops/log_event" {
                  input = {feature: "SEC-3", step: $step_name, outcome: "rejected", severity: "warn", user_id: 0, account_id: 0, entity_type: "mcp_server", entity_id: 8, correlation_id: "", error_code: "E-SEC-020", message: "The AI tool address refused a caller with no valid sign-in. At most 5 of these are logged per hour per reason.", metadata: {reason: $reason, logged_this_hour: ($recent + 1)}}
                } as $_logged
              }
            }
          }

          catch {
            var.update $log_refusal {
              value = false
            }
          }
        }
      }
    }
  }

  response = {
    allowed : $allowed
    user_id : $user_id
    reason  : $reason
    token_id: $agent_token_id
  }
}
