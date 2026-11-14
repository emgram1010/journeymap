// SEC-3 (2026-11-14) — "whose token is this?" Returns the caller's id and nothing else.
// Used by `usr/mcp_caller` to check a token presented at the AI tool address. Deliberately
// writes NO event: `auth/me` logs on every call, and this runs on every tool connection.
query "auth/whoami" verb=GET {
  api_group = "Authentication"
  auth = "user"

  input {
  }

  stack {
    var $id {
      value = $auth.id
    }
  }

  response = {id: $id}
}
