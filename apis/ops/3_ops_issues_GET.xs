// OBS-1 (US-OBS-1-07, issue list) — Admin-only. Lists grouped issues for
// the Health page's issue list. Acknowledgement (US-OBS-1-06) is
// deferred, so every issue found in the window is returned — there is no
// "hidden until it recurs" state yet.
query "ops/issues" verb=GET {
  api_group = "Ops"
  auth = "user"

  input {
    int account_id? {
      description = "Narrow to one account. Omitted = every account."
    }

    text since? filters=trim
  }

  stack {
    function.run "ops/require_platform_admin" {
      input = {user_id: $auth.id}
    } as $_admin_check

    function.run "ops/group_issues" {
      input = {account_id: $input.account_id, since: $input.since}
    } as $grouped
  }

  response = $grouped
}
