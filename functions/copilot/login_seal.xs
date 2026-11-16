// COP-6 story 02 - THE one place a connection login is sealed (encrypted) before it is stored. Founder decision 2026-11-16: logins are encrypted in Xano. The key lives in the workspace environment variable COPILOT_SECRET_KEY, never in the database, so a copy of the database alone cannot open a login. JWE (A256KW + A256GCM) is authenticated: a tampered value fails to open instead of opening to garbage. Never throws and never returns the value or the key: ok=false + E-COP-067 when the key is missing or too short (under 32 characters), so nothing is ever stored under a weak or empty key.
function "copilot/login_seal" {
  input {
    text value? {
      sensitive = true
    }
  }

  stack {
    var $key {
      value = $env.COPILOT_SECRET_KEY ?? ""
    }

    var $key_ok {
      value = ($key|strlen) >= 32
    }

    var $sealed {
      value = ""
    }

    conditional {
      if ($key_ok == true) {
        var.update $sealed {
          value = $input.value|jwe_encode:{}:$key:"A256KW":"A256GCM"
        }
      }
    }
  }

  response = {ok: $key_ok, sealed: $sealed, code: (($key_ok == true) ? "" : "E-COP-067")}
}
