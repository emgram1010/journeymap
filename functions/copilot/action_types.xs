// COP-2 story 01 — THE catalogue of copilot action types: the one place that says what each kind of action touches, whether it can be undone, its starting level (decision D-8) and whether it is locked. touches: internal | customer | booking | money. default_level: own (runs on its own) | tell (runs, then tells you) | wait (waits for you). locked = the owner cannot change it. person_only = never done by an AI at all, at any level (decision D-4: Publish version, Publish to live). wired = a copilot tool uses it today (the screen says so honestly when not). Generic on purpose: nothing here names an industry.
function "copilot/action_types" {
  input {
  }

  stack {
    var $types {
      value = {
        map_read           : {key: "map_read", name: "Read maps and plans", touches: "internal", reversible: true, default_level: "own", locked: true, person_only: false, has_limit: false, wired: true}
        map_draft          : {key: "map_draft", name: "Edit draft maps", touches: "internal", reversible: true, default_level: "own", locked: true, person_only: false, has_limit: false, wired: true}
        map_publish_version: {key: "map_publish_version", name: "Publish a map version", touches: "internal", reversible: false, default_level: "wait", locked: true, person_only: true, has_limit: false, wired: true}
        plan_draft         : {key: "plan_draft", name: "Draft a plan", touches: "internal", reversible: true, default_level: "own", locked: false, person_only: false, has_limit: false, wired: true}
        plan_live_change   : {key: "plan_live_change", name: "Change a day that is already live", touches: "internal", reversible: true, default_level: "wait", locked: true, person_only: false, has_limit: false, wired: true}
        plan_publish_live  : {key: "plan_publish_live", name: "Publish a plan to live", touches: "internal", reversible: false, default_level: "wait", locked: true, person_only: true, has_limit: false, wired: false}
        note_internal      : {key: "note_internal", name: "Write an internal note", touches: "internal", reversible: true, default_level: "tell", locked: false, person_only: false, has_limit: false, wired: true}
        work_update        : {key: "work_update", name: "Update assigned work", touches: "internal", reversible: true, default_level: "tell", locked: false, person_only: false, has_limit: false, wired: true}
        work_complete      : {key: "work_complete", name: "Mark its own work done or skipped", touches: "internal", reversible: true, default_level: "wait", locked: false, person_only: false, has_limit: false, wired: true}
        customer_message   : {key: "customer_message", name: "Send a message to a customer", touches: "customer", reversible: false, default_level: "wait", locked: false, person_only: false, has_limit: false, wired: false}
        booking_change     : {key: "booking_change", name: "Create or change a booking", touches: "booking", reversible: true, default_level: "wait", locked: false, person_only: false, has_limit: false, wired: false}
        money_payment      : {key: "money_payment", name: "Charge, pay or refund money", touches: "money", reversible: false, default_level: "wait", locked: false, person_only: false, has_limit: true, wired: false}
        scheduled_work     : {key: "scheduled_work", name: "Work on its tasks on a schedule, with nobody at the screen", touches: "internal", reversible: true, default_level: "wait", locked: false, person_only: false, has_limit: false, wired: true}
      }
    }

    var $order {
      value = ["map_read", "map_draft", "map_publish_version", "plan_draft", "plan_live_change", "plan_publish_live", "note_internal", "work_update", "work_complete", "customer_message", "booking_change", "money_payment", "scheduled_work"]
    }
  }

  response = {types: $types, order: $order}
}
