// LIVE-1 (US-LIVE-1-02) — Publish one timeline to live.
//
// NOT "publish version" (PUB-1, which freezes a journey map). This
// freezes a DAY and hands it to the person who has to do it.
//
// AFTER THIS, THE PLANNER AND THE PERFORMER SEE DIFFERENT THINGS, on
// purpose (decision D-23). The performer reads the frozen snapshot;
// the planner may keep rearranging the live plan. Every later change
// is written to `plan_change_log` so plan-vs-actual stays honest
// instead of quietly rewriting history. Verified live: a scheduled
// step re-timed from 30 to 55 minutes after publishing left the
// snapshot and its hash untouched, and produced one change-log row.
//
// EVERY BLOCKER IS RETURNED AT ONCE, with a count and a plain
// sentence. Publishing a day is a batch action — telling someone
// about one missing assignee, then another after they fix it, is the
// slowest possible way to get a day out.
//
// A FAILED PUBLISH WRITES NOTHING. The publication row and the
// timeline's `published` status go in one `db.transaction`, so there
// is no state where a timeline claims to be live without a snapshot
// behind it — which is exactly what the performer's view would then
// fail to find.
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

    db.query plan_publication {
      where = $db.plan_publication.timeline_id == $input.timeline_id
      return = {type: "count"}
    } as $already

    function.run "live/build_publication" {
      input = {timeline_id: $input.timeline_id}
    } as $pub

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($already > 0) {
        var.update $reject_code {
          value = "E-LIVE-005"
        }

        var.update $reject_msg {
          value = "This timeline is already published. (E-LIVE-005)"
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
            feature       : "LIVE-1"
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
            metadata      : {blockers: $pub.blockers}
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

    db.transaction {
      stack {
        db.add plan_publication {
          data = {
            timeline_id  : $input.timeline_id
            published_by : $actor.user_id
            published_at : $now_ms
            snapshot     : {items: $pub.items, canonical_version: "publication|v1"}
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

    function.run "ops/log_event" {
      input = {
        feature       : "LIVE-1"
        step          : "publish_timeline"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "plan_publication"
        entity_id     : $publication.id
        correlation_id: $input.correlation_id
        message       : "Timeline published to live."
        metadata      : {
          timeline_id  : $input.timeline_id
          item_count   : $pub.item_count
          snapshot_hash: $pub.snapshot_hash
        }
      }
    }
  }

  response = {
    publication : {id: $publication.id, timeline_id: $input.timeline_id, item_count: $pub.item_count, snapshot_hash: $pub.snapshot_hash}
    published_at: $now_ms
    items       : $pub.items
  }
}
