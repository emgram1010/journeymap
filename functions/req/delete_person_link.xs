// REQ-1 story 03 — a person on a plan takes their profile link with them. WRITE-ONLY helper called wherever a planner_agent is deleted (removing a person from a plan, deleting a whole plan), so no link is ever left pointing at a person who is gone. Reads the link first and deletes it by its own id (a delete by a shared field removes only the first match). Safe inside the caller's transaction. Nothing happens, and nothing is wrong, when the person had no link. Returns how many links were removed.
function "req/delete_person_link" {
  input {
    int planner_agent_id filters=min:1
  }

  stack {
    db.query planner_agent_profile {
      where = $db.planner_agent_profile.planner_agent_id == $input.planner_agent_id
      return = {type: "list"}
      output = ["id"]
    } as $rows

    foreach ($rows) {
      each as $r {
        db.del planner_agent_profile {
          field_name = "id"
          field_value = $r.id
        }
      }
    }
  }

  response = {removed: ($rows|count)}
}
