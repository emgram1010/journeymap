// COP-9 story 03 — THE hard limits on what a skill-library item may say. Called ONLY by
// copilot/skill_write, before anything is stored, whatever the approval level: no level, not even
// "runs on its own", reaches this check. Never throws; returns a code and a plain message, and the
// writer refuses.
//
// E-COP-083 (always, copilot or owner): something that looks like a secret (password, key, token)
// or customer personal data (an email address, a phone or card number). Checked first.
// E-COP-082 (copilot writes only): the item tries to grant the copilot a permission, change an
// approval level, approve something, or tell it to skip approval. An owner may write about
// approvals in their own words; the copilot may not teach itself to.
//
// Deliberately strict: a safe sentence that happens to use one of these phrases is refused too, and
// the copilot is told to reword it. A false refusal costs a rewrite; a false pass costs a bad rule.
//
// Engine notes (CLAUDE.md): no "|" inside a string literal (it breaks the parser), so each pattern
// is its own regex with no alternation; `|contains` is used on TEXT only (it is wrong on arrays);
// matches are counted with bool|to_int so there is no conditional inside the loops.
function "copilot/skill_limits" {
  input {
    text title? filters=trim
    text body? filters=trim
    text condition_text? filters=trim
    text scope_text? filters=trim
    text reason? filters=trim
    bool check_permissions?
  }

  stack {
    var $text {
      value = ($input.title ~ " \n " ~ $input.body ~ " \n " ~ $input.condition_text ~ " \n " ~ $input.scope_text ~ " \n " ~ $input.reason)|lower
    }

    // ── E-COP-083: secrets and customer personal data ──
    var $secret_words {
      value = ["password", "passcode", "passwd", "api key", "api_key", "apikey", "secret key", "client secret", "access token", "auth token", "refresh token", "bearer ", "private key", "login details", "username and password", "credit card", "card number", "cvv", "iban", "bank account number", "social security", "date of birth"]
    }

    var $secret_hits {
      value = 0
    }

    foreach ($secret_words) {
      each as $w {
        var.update $secret_hits {
          value = $secret_hits + (($text|contains:$w)|to_int)
        }
      }
    }

    var $secret_patterns {
      value = ["/[a-z0-9._%+-]+@[a-z0-9-]+[.][a-z0-9.-]+/", "/[(]?[0-9]{3}[)]?[ .-]?[0-9]{3}[ .-]?[0-9]{4}/", "/([0-9][ -]?){13,19}/", "/[spr]k[-_][a-z0-9_-]{16,}/", "/[a-f0-9]{32,}/", "/[a-z0-9+=_-]{40,}/", "/eyj[a-z0-9_-]{10,}[.]/"]
    }

    foreach ($secret_patterns) {
      each as $pat {
        var.update $secret_hits {
          value = $secret_hits + (($pat|regex_matches:$text)|to_int)
        }
      }
    }

    // ── E-COP-082: permissions and approvals (copilot writes only) ──
    var $perm_words {
      value = ["approval level", "approval setting", "change the level", "raise the level", "set the level", "lower the level", "skip approval", "skip the approval", "skip approvals", "bypass", "auto-approve", "auto approve", "approve it yourself", "approve on behalf", "approve the action", "approve actions", "mark it approved", "mark as approved", "grant yourself", "grant itself", "grant permission", "give yourself permission", "give itself permission", "permission to", "elevate", "run on its own", "runs on its own", "no need to ask the owner", "don't need approval", "do not need approval", "doesn't need approval", "does not need approval", "ignore the gate", "override the gate", "switch off the gate", "publish to live yourself", "publish the version yourself"]
    }

    var $perm_hits {
      value = 0
    }

    foreach ($perm_words) {
      each as $pw {
        var.update $perm_hits {
          value = $perm_hits + (($text|contains:$pw)|to_int)
        }
      }
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    conditional {
      if ($secret_hits > 0) {
        var.update $code {
          value = "E-COP-083"
        }

        var.update $message {
          value = "A skill can't contain logins, passwords, keys or customer personal details. Nothing was saved. (E-COP-083)"
        }
      }

      elseif ($input.check_permissions == true && $perm_hits > 0) {
        var.update $code {
          value = "E-COP-082"
        }

        var.update $message {
          value = "A skill can't give the copilot permissions, change an approval level, or approve or skip approvals. Nothing was saved. (E-COP-082)"
        }
      }
    }
  }

  response = {code: $code, message: $message, secret_hits: $secret_hits, perm_hits: $perm_hits}
}
