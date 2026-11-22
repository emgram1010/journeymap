// AIM-1 — the AI members screen's data, for an admin who is a person (aim/overview holds every rule). No email, token or secret is returned.
query "admin/ai_members" verb=GET {
  api_group = "Members & Accounts"
  auth = "user"

  input {
  }

  stack {
    function.run "aim/overview" {
      input = {actor_user_id: $auth.id}
    } as $o
  }

  response = $o
}
