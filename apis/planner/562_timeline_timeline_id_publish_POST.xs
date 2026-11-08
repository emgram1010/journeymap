// LIVE-1 (US-LIVE-1-02) + REPUB-1 (US-REPUB-1-03) — Publish one
// timeline to live; and publish it AGAIN, up until the moment the
// agent starts working it.
//
// NOT "publish version" (PUB-1, which freezes a journey map). This
// freezes a DAY and hands it to the person who has to do it.
//
// AFTER THIS, THE PLANNER AND THE PERFORMER SEE DIFFERENT THINGS, on
// purpose (decision D-23). The performer reads the frozen snapshot;
// the planner may keep rearranging the live plan. Every later change
// is written to `plan_change_log` so plan-vs-actual stays honest
// instead of quietly rewriting history.
//
// REPUBLISH (REPUB-1, founder decision 2026-11-01): a published day
// may be published again — a NEW plan_publication row, version n+1;
// old versions stay forever as history and every reader takes the
// current one through live/latest_publications. THE SEAL: any
// activity_log event recorded against ANY of this timeline's
// publications (a started, but also a blocked or a note — any
// engagement) means the agent has begun the day, and republish is
// refused with E-LIVE-007. Once an event lands, the day is final.
// E-LIVE-005 ("already published") is RETIRED — being published is no
// longer a reason to refuse; being WORKED is. E-LIVE-006 is NOT
// touched: the catalog already uses it for "the write failed partway
// and rolled back", and one code means one thing (GUARD-REG-01 —
// which is how the first draft of this epic, reusing 006 for the
// seal, was caught before it shipped).
//
// THE RACE GUARD IS THE DATABASE'S OWN (EXC-1 lesson, verified live:
// db.transaction does NOT serialize overlapping requests). The next
// version number is computed from the SAME read the seal check used,
// and (timeline_id, version) is UNIQUE — two overlapping publishes
// compute the same n+1, the second insert is refused, its transaction
// rolls back, and it is reported as E-LIVE-008, logged, never silent.
//
// EVERY BLOCKER IS RETURNED AT ONCE, with a count and a plain
// sentence — and the same blockers gate a republish, because a
// republished day is a brand-new promise and must clear the same bar.
//
// A FAILED PUBLISH WRITES NOTHING. The publication row and the
// timeline's `published` status go in one `db.transaction`, so there
// is no state where a timeline claims to be live without a snapshot
// behind it — which is exactly what the performer's view would then
// fail to find.
//
// TW-1 (2026-11-04): the snapshot's canonical_version comes from
// live/build_publication (publication|v2 carries each job's time
// window), falling back to v1 for a builder that doesn't report one.
//
// `GET` the same path to preview blockers without publishing.
query "timeline/{timeline_id}/publish" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int timeline_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "planner/assert_timeline" {
      input = {account_id: $actor.account_id, timeline_id: $input.timeline_id}
    } as $guard

    function.run "guards/assert_not_archived" {
      input = {
        is_archived: $guard.workspace.is_archived
        feature    : "LIVE-1"
        step       : "publish_timeline"
        entity_type: "planner_timeline"
        entity_id  : $input.timeline_id
        user_id    : $actor.user_id
        account_id : $actor.account_id
      }
    }

    // Every publication so far — ONE read drives everything below: is
    // this a republish, which version comes next, and which rows the
    // seal check scans. The number claimed comes from the SAME read
    // the checks used (EXC-1); a true overlap is settled by the
    // unique index, not by this read.
    db.query plan_publication {
      where = $db.plan_publication.timeline_id == $input.timeline_id
      return = {type: "list"}
    } as $prior

    var $pub_ids {
      value = []
    }

    var $cur_version {
      value = 0
    }

    var $gt {
      value = 0
    }

    foreach ($prior) {
      each as $p {
        array.push $pub_ids {
          value = $p.id
        }

        var.update $gt {
          value = ($p.version > $cur_version)|to_int
        }

        var.update $cur_version {
          value = $cur_version + (($p.version - $cur_version) * $gt)
        }
      }
    }

    var $next_version {
      value = $cur_version + 1
    }

    var $is_republish {
      value = ($cur_version > 0)
    }

    var $feature {
      value = "LIVE-1"
    }

    conditional {
      if ($is_republish == true) {
        var.update $feature {
          value = "REPUB-1"
        }
      }
    }

    // THE SEAL: any event against ANY of this timeline's publications
    // (belt and braces — not just the latest) means work has begun.
    var $activity_count {
      value = 0
    }

    conditional {
      if (($pub_ids|count) > 0) {
        db.query activity_log {
          where = $db.activity_log.plan_publication_id in $pub_ids
          return = {type: "count"}
        } as $acts

        var.update $activity_count {
          value = $acts
        }
      }
    }

    function.run "live/build_publication" {
      input = {timeline_id: $input.timeline_id}
    } as $pub

    var $canonical_version {
      value = $pub.canonical_version ?? "publication|v1"
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    // Seal first: a sealed day is sealed whatever else is wrong with it.
    conditional {
      if ($is_republish == true && $activity_count > 0) {
        db.get planner_agent {
          field_name = "id"
          field_value = $guard.timeline.agent_id
        } as $seal_agent

        var $agent_name {
          value = ($seal_agent.name ?? "")
        }

        var $who {
          value = "The performer"
        }

        conditional {
          if ($agent_name != "") {
            var.update $who {
              value = $agent_name
            }
          }
        }

        var.update $reject_code {
          value = "E-LIVE-007"
        }

        var.update $reject_msg {
          value = $who ~ " has already started this day — it can no longer be republished. (E-LIVE-007)"
        }
      }
    }

    var $first_blocker {
      value = ""
    }

    conditional {
      if (($pub.blockers|count) > 0) {
        var.update $first_blocker {
          value = ($pub.blockers|first).message
        }
      }
    }

    conditional {
      if ($reject_code == "" && ($pub.blockers|count) > 0) {
        var.update $reject_code {
          value = ($pub.blockers|first).code
        }

        var.update $reject_msg {
          value = $first_blocker
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : $feature
            step          : "publish_timeline"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_timeline"
            entity_id     : $input.timeline_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Publish to live refused."
            metadata      : {blockers: $pub.blockers, activity_count: $activity_count, current_version: $cur_version}
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "inputerror"
      error = $reject_msg
    }

    var $now_ms {
      value = now|to_int
    }

    var $txn_ok {
      value = false
    }

    var $new_pub_id {
      value = 0
    }

    try_catch {
      try {
        db.transaction {
          stack {
            db.add plan_publication {
              data = {
                timeline_id  : $input.timeline_id
                version      : $next_version
                published_by : $actor.user_id
                published_at : $now_ms
                snapshot     : {items: $pub.items, canonical_version: $canonical_version}
                snapshot_hash: $pub.snapshot_hash
                item_count   : $pub.item_count
              }
            } as $publication

            db.patch planner_timeline {
              field_name = "id"
              field_value = $input.timeline_id
              data = {status: "published", updated_at: "now"}
            } as $patched
          }
        }

        var.update $new_pub_id {
          value = $publication.id
        }

        var.update $txn_ok {
          value = true
        }
      }

      catch {
        // The race loser: its (timeline_id, version) was refused by the
        // unique index and the whole transaction rolled back. Logged,
        // never silent (OBS-1).
        function.run "ops/log_event" {
          input = {
            feature       : $feature
            step          : "publish_timeline"
            outcome       : "failure"
            severity      : "warn"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "planner_timeline"
            entity_id     : $input.timeline_id
            correlation_id: $input.correlation_id
            error_code    : "E-LIVE-008"
            message       : "Publish to live lost a concurrent publish and wrote nothing."
            metadata      : {attempted_version: $next_version}
          }
        }
      }
    }

    var $race_msg {
      value = "This day was just published by someone else — reload and try again. (E-LIVE-008)"
    }

    precondition ($txn_ok == true) {
      error_type = "inputerror"
      error = $race_msg
    }

    function.run "ops/log_event" {
      input = {
        feature       : $feature
        step          : "publish_timeline"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "plan_publication"
        entity_id     : $new_pub_id
        correlation_id: $input.correlation_id
        message       : "Timeline published to live."
        metadata      : {
          timeline_id  : $input.timeline_id
          item_count   : $pub.item_count
          snapshot_hash: $pub.snapshot_hash
          from_version : $cur_version
          to_version   : $next_version
        }
      }
    }
  }

  response = {
    publication : {id: $new_pub_id, timeline_id: $input.timeline_id, version: $next_version, item_count: $pub.item_count, snapshot_hash: $pub.snapshot_hash}
    published_at: $now_ms
    is_republish: $is_republish
    items       : $pub.items
  }
}
