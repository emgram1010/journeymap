// REQ-1 story 03 — a repeated plan's people carry the link their source row had. WRITE-ONLY helper called by the repeat right after it makes the copy of a person: if the SOURCE person is tied to a lasting profile, the new person is tied to the same one (linked_how "repeat"); if the source had no link, nothing is written. Called for every person without a condition in the caller's loop (a conditional that reads a value set earlier in the same iteration silently loses its writes, CLAUDE.md): the decision is made in here. Safe inside the caller's transaction. Returns whether a link was copied.
function "req/copy_person_link" {
  input {
    int account_id filters=min:1
    int from_agent_id filters=min:1
    int to_agent_id filters=min:1
    int user_id?
  }

  stack {
    db.query planner_agent_profile {
      where = $db.planner_agent_profile.planner_agent_id == $input.from_agent_id
      return = {type: "single"}
    } as $src

    var $profile_id {
      value = $src|get:"agent_profile_id":0
    }

    var $copied {
      value = false
    }

    conditional {
      if ($profile_id != 0) {
        db.add planner_agent_profile {
          data = {
            account_id      : $input.account_id
            planner_agent_id: $input.to_agent_id
            agent_profile_id: $profile_id
            linked_how      : "repeat"
            linked_by       : $input.user_id
          }
        } as $added

        var.update $copied {
          value = true
        }
      }
    }
  }

  response = {copied: $copied}
}
