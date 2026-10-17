// PLN-3 / P3A-1 (US-P3A-1-02) — "Has anything actually happened on this
// plan yet?" This is the single gate that decides whether a plan may be
// deleted or must be archived.
//
// IMPLEMENTED 2026-10-16. It previously returned "no history" for every
// plan on earth, because it was written when all three tables it needs
// were still unbuilt and it simply added up three hardcoded zeros. JOB-1,
// LIVE-1 and LOG-1 have all shipped since; the TODOs were never filled
// in, so the stub quietly became wrong rather than merely incomplete —
// a plan with real recorded work would have sailed through its own
// safety check. Found during PLN-9 while shipping the agent/timeline
// deletes; plan delete itself is still held, so nothing acted on the
// wrong answer in the meantime.
//
// THREE THINGS COUNT AS HISTORY, and any one of them is enough:
//   1. a job exists in this plan                       (work_item, JOB-1)
//   2. one of its days has been published to live      (plan_publication,
//      reached via this plan's timelines, LIVE-1)
//   3. someone has actually recorded work              (activity_log,
//      reached via this plan's jobs, LOG-1)
//
// Checks 2 and 3 are guarded by an id-list count first: an `in` clause
// against an empty array is not worth relying on, and the surrounding
// `conditional` is the same shape planner/assert_maps_publishable
// already uses live. Their conditions read a list built by a loop that
// has already finished, never a var updated in the same iteration
// (CLAUDE.md).
//
// Counting activity_log through the plan's jobs is sufficient even
// though the log also carries plan_publication_id: a log row implies a
// publication, and a publication alone already trips check 2.
function "planner/workspace_has_history" {
  input {
    int workspace_id filters=min:1
  }

  stack {
    // 1) Jobs in this plan. Fetched as a list, not a count, because the
    // ids are needed again for the activity_log check below.
    db.query work_item {
      where = $db.work_item.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $jobs

    var $job_count {
      value = $jobs|count
    }

    var $job_ids {
      value = []
    }

    foreach ($jobs) {
      each as $j {
        array.push $job_ids {
          value = $j.id
        }
      }
    }

    // 2) Published days. plan_publication points at a timeline, not at
    // a plan, so this plan's timeline ids come first.
    db.query planner_timeline {
      where = $db.planner_timeline.workspace_id == $input.workspace_id
      return = {type: "list"}
    } as $timelines

    var $timeline_ids {
      value = []
    }

    foreach ($timelines) {
      each as $tl {
        array.push $timeline_ids {
          value = $tl.id
        }
      }
    }

    var $publication_count {
      value = 0
    }

    conditional {
      if (($timeline_ids|count) > 0) {
        db.query plan_publication {
          where = $db.plan_publication.timeline_id in $timeline_ids
          return = {type: "count"}
        } as $pubs

        var.update $publication_count {
          value = $pubs
        }
      }
    }

    // 3) Recorded work, reached through this plan's jobs.
    var $log_count {
      value = 0
    }

    conditional {
      if (($job_ids|count) > 0) {
        db.query activity_log {
          where = $db.activity_log.work_item_id in $job_ids
          return = {type: "count"}
        } as $logs

        var.update $log_count {
          value = $logs
        }
      }
    }

    var $total {
      value = $job_count + $publication_count + $log_count
    }
  }

  response = {
    has_history      : ($total > 0)
    job_count        : $job_count
    publication_count: $publication_count
    log_count        : $log_count
    checked          : ["work_item", "plan_publication", "activity_log"]
  }
}
