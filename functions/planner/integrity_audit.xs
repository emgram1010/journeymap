// PLN-8 (US-PLN-8-02) — The planner's safety net: run every integrity
// check for one account and return what is broken. Read-only.
//
// Xano declares foreign keys but does not enforce referential actions,
// so nothing stops a bad write from leaving a row pointing at a
// deleted parent. Each epic tests its own entity; this checks what
// happens BETWEEN them, which is where corruption actually lives.
//
// IT NEVER REPAIRS ANYTHING (PLN-8 Non-Goals). It reports ids and a
// human decides. An auto-repair that guessed wrong would turn a
// detectable problem into a silent one.
//
// The ten checks live in four functions rather than here, because a
// single function holding all of them failed at runtime with
// "Invalid syntax" — there is an apparent complexity ceiling. Each
// part is independently runnable, which is better for diagnosis
// anyway: when the audit fires you can re-run just the failing part.
//
// This matters most for the delete paths that are still awaiting
// approval. Orphaned children are exactly what a wrong cascade
// produces, and this is what will prove the cascades correct once
// they are allowed to run.
function "planner/integrity_audit" {
  input {
    int account_id filters=min:1
  }

  stack {
    function.run "planner/audit_agents" {
      input = {account_id: $input.account_id}
    } as $agents_result

    function.run "planner/audit_timelines" {
      input = {account_id: $input.account_id}
    } as $timelines_result

    function.run "planner/audit_tasks" {
      input = {account_id: $input.account_id}
    } as $tasks_result

    function.run "planner/audit_sequences" {
      input = {account_id: $input.account_id}
    } as $sequences_result

    var $violations {
      value = []
    }

    foreach ($agents_result.violations) {
      each as $v {
        array.push $violations {
          value = $v
        }
      }
    }

    foreach ($timelines_result.violations) {
      each as $v {
        array.push $violations {
          value = $v
        }
      }
    }

    foreach ($tasks_result.violations) {
      each as $v {
        array.push $violations {
          value = $v
        }
      }
    }

    foreach ($sequences_result.violations) {
      each as $v {
        array.push $violations {
          value = $v
        }
      }
    }
  }

  response = {
    account_id     : $input.account_id
    clean          : (($violations|count) == 0)
    violation_count: ($violations|count)
    violations     : $violations
  }
}
