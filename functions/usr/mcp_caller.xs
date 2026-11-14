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
// `usr/assert_module_access` itself. A missing or bad token is NOT logged yet — a public
// address could flood the log; see US-SEC-3-05.
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

    conditional {
      if ($token != "") {
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
  }

  response = {
    allowed: $allowed
    user_id: $user_id
    reason : $reason
  }
}
