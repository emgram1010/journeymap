// CAT-1 — Shared key/label format check, used by all four create/update
// endpoints (item_type POST/PATCH, method POST/PATCH). Put in its own
// function because the same two rules apply identically on both tables
// and at both verbs — four call sites sharing one rule is exactly the
// "put a shared RULE in its own function" case (CLAUDE.md), not the
// boilerplate case (see catalog/resolve_actor's header for why THAT one
// stays duplicated instead).
//
// Returns ok=true with no code when both fields pass. Callers run this
// FIRST in their own reject_code chain (precedence: format, then
// duplicate-key, then cross-account/admin, matching the agent_profile
// endpoints' existing precedence style) and only act on it when
// ok == false, keeping the branch condition on an input/loop-item shape
// (CLAUDE.md's conditional-on-earlier-var trap does not apply here since
// callers branch on this function's OWN response, read once).
//
// Length checks use |strlen (confirmed working, apis/planner/550_template_POST.xs).
// The key check mirrors the STORED value exactly: the table column only
// applies `filters=trim|lower` (trim + lowercase, nothing else), so the
// pattern is tested against trim+lower here too, not a slugified form —
// a slugify suggestion is a frontend-only convenience
// (webapp/protype-2/src/catalog/catalogValidation.ts::normaliseKey).
function "catalog/validate_key_and_label" {
  input {
    text key? filters=trim
    text label? filters=trim
  }

  stack {
    var $key_stored {
      value = $input.key|lower
    }

    var $key_len {
      value = $key_stored|strlen
    }

    var $key_ok {
      value = ($key_len >= 2 && $key_len <= 40 && ("/^[a-z0-9][a-z0-9-]*$/"|regex_matches:$key_stored))
    }

    var $label_len {
      value = $input.label|strlen
    }

    var $label_ok {
      value = ($label_len >= 1 && $label_len <= 80 && ("/<[a-zA-Z][^>]*>/"|regex_matches:$input.label) == false)
    }

    var $ok {
      value = true
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    conditional {
      if ($key_ok == false) {
        var.update $ok {
          value = false
        }

        var.update $code {
          value = "E-CAT-001"
        }

        var.update $message {
          value = "Use a short id with letters, numbers and hyphens, like chair-resin. (E-CAT-001)"
        }
      }
    }

    conditional {
      if ($ok == true && $label_ok == false) {
        var.update $ok {
          value = false
        }

        var.update $code {
          value = "E-CAT-003"
        }

        var.update $message {
          value = "Give it a name up to 80 characters, with no HTML. (E-CAT-003)"
        }
      }
    }
  }

  response = {ok: $ok, code: $code, message: $message, key_stored: $key_stored}
}
