//  USR-1 (US-USR-1-07) — An admin corrects a person's name or email.
// 
//  `PATCH user/edit_profile` edits the caller's OWN record. This one is the admin's version —
//  fixing a colleague's misspelled name, or moving them to a new work address.
// 
//  SELF-EDITING IS ALLOWED HERE, unlike role and status. Role is not editable through this
//  endpoint at all; that is `admin/user_role`, and it keeps its own guards.
// 
//  AN OMITTED FIELD MEANS "LEAVE IT". An omitted optional text input arrives as "", never null
//  (CLAUDE.md), so this endpoint cannot be used to blank a name or an email.
// 
//  COP-1 review (2026-11-14): the copilot's email can never be changed (E-COP-012).
// Shaped: db.edit returns every column, password included.
query "admin/user_update" verb=POST {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    // The person being corrected.
    int user_id
  
    // Leave either out to keep what is already there.
    text name? filters=trim
  
    text email? filters=trim|lower
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "admin/user_update"
        entity_id    : $input.user_id
      }
    } as $admin_user
  
    var $has_something {
      value = ($input.name != "" || $input.email != "")
    }
  
    precondition ($has_something) {
      error_type = "inputerror"
      error = "A name and an email address are both needed. (E-USR-011)"
    }
  
    db.get user {
      field_name = "id"
      field_value = $input.user_id
      output = ["id", "name", "email", "account_id", "role"]
    } as $target_user
  
    precondition ($target_user != null) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }
  
    // Same answer whether the person is missing or in another account.
    precondition ($admin_user.account_id == $target_user.account_id) {
      error_type = "notfound"
      error = "We couldn't find that person in your account. (E-USR-002)"
    }

    // SAFE-1 / D-10 (2026-11-21): the account owner is changed only by the owner themself.
    // One shared rule (usr/assert_owner_untouched); it logs its own refusal (E-SAFE-008).
    function.run "usr/assert_owner_untouched" {
      input = {actor_user_id: $auth.id, target_user_id: $target_user.id, step: "admin/user_update"}
    } as $_owner_guard
  
    // COP-1 review (2026-11-14): the copilot's address is the reason it can never sign in
    // (`.invalid` cannot receive a reset or magic link). Changing it to a real inbox would let an
    // admin sign in AS the copilot and act outside the tool gate — no cap, no tool_call_log row.
    // Its name may still be corrected.
    function.run "copilot/identity_for_user" {
      input = {user_id: $target_user.id}
    } as $target_ai
  
    var $copilot_email_change {
      value = ($target_ai.is_ai == true && $input.email != "" && $input.email != $target_user.email)
    }
  
    precondition ($copilot_email_change == false) {
      error_type = "accessdenied"
      error = "The copilot's email address can't be changed — it is what stops anyone signing in as the copilot. You can still rename it. (E-COP-012)"
    }
  
    var $next_name {
      value = $target_user.name
    }
  
    conditional {
      if ($input.name != "") {
        var.update $next_name {
          value = $input.name
        }
      }
    }
  
    var $next_email {
      value = $target_user.email
    }
  
    conditional {
      if ($input.email != "") {
        var.update $next_email {
          value = $input.email
        }
      }
    }
  
    var $email_looks_right {
      value = "/^[^@ ]+@[^@ ]+[.][^@ ]+$/"|regex_matches:$next_email
    }
  
    precondition ($email_looks_right) {
      error_type = "inputerror"
      error = "That doesn't look like an email address. (E-USR-014)"
    }
  
    db.get user {
      field_name = "email"
      field_value = $next_email
      output = ["id"]
    } as $email_owner
  
    var $email_owner_id {
      value = $email_owner|get:"id":0
    }
  
    var $email_is_free {
      value = ($email_owner_id == 0 || $email_owner_id == $target_user.id)
    }
  
    precondition ($email_is_free) {
      error_type = "inputerror"
      error = "That email address is already in use. (E-USR-008)"
    }
  
    db.edit user {
      field_name = "id"
      field_value = $target_user.id
      enforce_hidden_fields = false
      data = {name: $next_name, email: $next_email}
    } as $updated_user
  
    // WHICH fields changed, not what they changed to.
    function.run "Getting Started Template/create_event_log" {
      input = {
        user_id   : $admin_user.id
        account_id: $admin_user.account_id
        action    : "updated_user_profile"
        metadata  : {
        target_user_id: $target_user.id
        name_changed  : ($next_name != $target_user.name)
        email_changed : ($next_email != $target_user.email)
      }
      }
    } as $event_log
  }

  response = {
    id        : $updated_user.id
    name      : $updated_user.name
    email     : $updated_user.email
    account_id: $updated_user.account_id
    role      : $updated_user.role
  }

  tags = ["phase-5", "usr-1"]
}