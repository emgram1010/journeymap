// COP-6 story 01 — add an outside system to the account's connections library. General: a key, a
// name and a short description; nothing here knows any particular system. Account admins only,
// never an AI identity. A key the account already has is refused (unique index as the real guard).
// Refusals: E-COP-025 (AI), E-COP-064 (key / name / description rule), E-COP-066 (key taken).
query "copilot/connection" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    text key? filters=trim|lower
    text name? filters=trim
    text description? filters=trim
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {actor_user_id: $auth.id, step: "copilot/connection", entity_id: 0}
    } as $admin_user

    function.run "copilot/identity_for_user" {
      input = {user_id: $auth.id}
    } as $me_ai

    precondition ($me_ai.is_ai == false) {
      error_type = "accessdenied"
      error = "Only a person can do this. It is ready for the owner to do themselves. (E-COP-025)"
    }

    var $key_ok {
      value = ("/^[a-z0-9-]{2,40}$/"|regex_matches:$input.key)
    }

    var $name_len {
      value = $input.name|strlen
    }

    var $desc_len {
      value = $input.description|strlen
    }

    precondition ($key_ok == true && $name_len >= 1 && $name_len <= 80 && $desc_len <= 300) {
      error_type = "inputerror"
      error = "A connection needs a short key (lower-case letters, digits and dashes, 2 to 40), a name (up to 80 characters) and a description of up to 300. (E-COP-064)"
    }

    db.query copilot_connection {
      where = $db.copilot_connection.account_id == $admin_user.account_id && $db.copilot_connection.key == $input.key
      return = {type: "count"}
    } as $taken

    precondition ($taken == 0) {
      error_type = "inputerror"
      error = "This account already has a connection with that key. Pick another key. (E-COP-066)"
    }

    db.add copilot_connection {
      data = {
        account_id        : $admin_user.account_id
        key               : $input.key
        name              : $input.name
        description       : $input.description
        status            : "available"
        created_by_user_id: $auth.id
        updated_at        : "now"
      }
    } as $added

    function.run "ops/log_event" {
      input = {feature: "COP-6", step: "connection_added", outcome: "success", severity: "info", error_code: "", message: "A connection was added to the library.", user_id: $auth.id, account_id: $admin_user.account_id, entity_type: "copilot_connection", entity_id: $added.id, metadata: {key: $input.key}}
    } as $_logged
  }

  response = {id: $added.id, key: $added.key, name: $added.name, description: $added.description, status: $added.status}
  tags = ["cop-6"]
}
