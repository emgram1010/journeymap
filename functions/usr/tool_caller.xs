// COP-1 — "who is this tool working for?" The one place a tool finds its caller. A tool has no $auth (proven live 2026-11-14). If a run ticket is passed it is looked up and is the ONLY thing consulted (in-app agent); with no ticket, the request's own token is checked via usr/mcp_caller (outside assistant). The person must be switched on and hold the Intelligent Layer (usr/assert_module_access). Also reports the context: "outside" when the request came in on the tool address (/x2/mcp/...), otherwise "inapp" — the caller cannot choose this. Never throws: returns allowed false with a reason. The ticket is never logged or returned.
function "usr/tool_caller" {
  input {
    text ticket? filters=trim
  }

  stack {
    var $allowed {
      value = false
    }

    var $user_id {
      value = 0
    }

    var $account_id {
      value = 0
    }

    var $via {
      value = "none"
    }

    var $reason {
      value = "no_token"
    }

    var $ticket_map_id {
      value = 0
    }

    var $ticket_architecture_id {
      value = 0
    }

    var $authz {
      value = ""
    }

    var $uri {
      value = ""
    }

    try_catch {
      try {
        var $hdrs {
          value = $env.$http_headers ?? {}
        }

        var.update $authz {
          value = $hdrs|get:"Authorization":""
        }

        var.update $uri {
          value = $env.$request_uri ?? ""
        }
      }

      catch {
        var.update $authz {
          value = ""
        }
      }
    }

    var $is_outside {
      value = "/^.x2.mcp./"|regex_matches:$uri
    }

    var $context {
      value = "inapp"
    }

    conditional {
      if ($is_outside) {
        var.update $context {
          value = "outside"
        }
      }
    }

    conditional {
      if ($input.ticket != "") {
        var.update $via {
          value = "ticket"
        }

        var.update $reason {
          value = "bad_ticket"
        }

        db.query tool_run_ticket {
          where = $db.tool_run_ticket.ticket == $input.ticket
          return = {type: "single"}
        } as $row

        var $row_id {
          value = $row|get:"id":0
        }

        var $expires {
          value = $row|get:"expires_at":0
        }

        var $now_ms {
          value = now|to_int
        }

        conditional {
          if ($row_id != 0 && $expires > $now_ms) {
            var.update $user_id {
              value = $row|get:"user_id":0
            }

            var.update $ticket_map_id {
              value = $row|get:"journey_map_id":0
            }

            var.update $ticket_architecture_id {
              value = $row|get:"journey_architecture_id":0
            }

            var.update $reason {
              value = "not_allowed"
            }
          }

          elseif ($row_id != 0) {
            var.update $reason {
              value = "expired_ticket"
            }
          }
        }

        conditional {
          if ($user_id != 0) {
            try_catch {
              try {
                function.run "usr/assert_module_access" {
                  input = {
                    actor_user_id: $user_id
                    module       : "intelligence"
                    step         : "tool/ticket"
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
      }

      else {
        function.run "usr/mcp_caller" {
          input = {
            authorization: $authz
            uri          : $uri
          }
        } as $who

        var.update $via {
          value = "token"
        }

        var.update $reason {
          value = $who.reason
        }

        var.update $allowed {
          value = $who.allowed == true
        }

        var.update $user_id {
          value = $who.user_id
        }
      }
    }

    conditional {
      if ($allowed == true) {
        db.query user {
          where = $db.user.id == $user_id
          return = {type: "single"}
          output = ["id", "account_id"]
        } as $user_row

        var.update $account_id {
          value = $user_row|get:"account_id":0
        }
      }
    }
  }

  response = {
    allowed               : $allowed
    user_id               : $user_id
    account_id            : $account_id
    via                   : $via
    context               : $context
    reason                : $reason
    ticket_map_id         : $ticket_map_id
    ticket_architecture_id: $ticket_architecture_id
  }
}
