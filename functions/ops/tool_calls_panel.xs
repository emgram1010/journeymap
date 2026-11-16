// COP-1 story 04 - the Health page view of AI tool calls (tool_call_log): the last 24 hours, how many were allowed or refused, from inside Emgram or from an outside assistant, and the 20 newest refusals with their code. Platform-wide, for support. Counts are folded in with bool|to_int (no conditional in the loop); the refusal list branches on the LOOP ITEM only (CLAUDE.md). Never returns a call's content - the log stores none.
function "ops/tool_calls_panel" {
  input {
  }

  stack {
    var $now_ms {
      value = now|to_int
    }

    var $cutoff {
      value = $now_ms - 86400000
    }

    db.query tool_call_log {
      where = $db.tool_call_log.created_at >= $cutoff
      sort = {tool_call_log.created_at: "desc"}
      return = {type: "list"}
      output = ["id", "created_at", "user_id", "account_id", "tool", "kind", "context", "verdict", "code"]
    } as $rows

    var $total {
      value = 0
    }

    var $allowed {
      value = 0
    }

    var $refused {
      value = 0
    }

    var $outside {
      value = 0
    }

    var $writes {
      value = 0
    }

    var $refusals {
      value = []
    }

    foreach ($rows) {
      each as $r {
        var.update $total {
          value = $total + 1
        }

        var.update $allowed {
          value = $allowed + (($r.verdict == "allowed")|to_int)
        }

        var.update $refused {
          value = $refused + (($r.verdict == "refused")|to_int)
        }

        var.update $outside {
          value = $outside + (($r.context == "outside")|to_int)
        }

        var.update $writes {
          value = $writes + (($r.kind == "write")|to_int)
        }

        conditional {
          if ($r.verdict == "refused") {
            array.push $refusals {
              value = {id: $r.id, at: $r.created_at, tool: $r.tool, code: $r.code, context: $r.context, account_id: $r.account_id, user_id: $r.user_id}
            }
          }
        }
      }
    }

    var $recent_refusals {
      value = $refusals|slice:0:20
    }
  }

  response = {since_hours: 24, total: $total, allowed: $allowed, refused: $refused, outside: $outside, writes: $writes, recent_refusals: $recent_refusals}
}
