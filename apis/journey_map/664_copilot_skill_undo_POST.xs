// COP-9 story 04 — one-click Undo: an account admin puts a skill-library item back to an earlier
// version. The screen's "Undo" on a change sends the version BEFORE it. Saved as a new version
// (copilot/skill_undo), so nothing is lost and the undo can itself be undone. A signed-in person
// only - never an AI identity (copilot/assert_person_only). The account is the admin's own, never
// taken from the request. Failures: E-COP-085.
query "copilot/skill_undo" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int skill_id?
    int restore_version_no?
    text reason? filters=trim
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id : $auth.id
        step          : "copilot/skill_undo"
        entity_id     : 0
        correlation_id: ""
      }
    } as $admin_user

    function.run "copilot/assert_person_only" {
      input = {
        user_id    : $auth.id
        account_id : $admin_user.account_id
        step       : "copilot/skill_undo"
        entity_type: "copilot_skill"
        entity_id  : $input.skill_id
      }
    } as $_person

    function.run "copilot/skill_undo" {
      input = {
        account_id        : $admin_user.account_id
        actor_user_id     : $auth.id
        skill_id          : $input.skill_id
        restore_version_no: $input.restore_version_no
        reason            : $input.reason
      }
    } as $undone
  }

  response = $undone
  tags = ["cop-9"]
}
