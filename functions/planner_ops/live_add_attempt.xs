// DEMAND-1 story 01 (decision D-11) — ONE attempt to add a job to a day that is already live, all inside one transaction, so a failed attempt leaves nothing behind. Called only by planner_ops/add_job_to_live_day, which checks who is asking and retries a lost race. THE ADD-ONLY RULE: the day's current snapshot is read, every frozen block is copied UNCHANGED and in the same order, and only this job's new blocks are put after the last one (their order numbers continue from the frozen day's highest). Nothing else on the live plan is swept in. Before writing, the new day's canonical text must start with the old day's canonical text, byte for byte (E-DEMAND-006) - the proof that planned work did not move. The job's cards are put on the day through planner_ops/schedule_card (the one rule a person's click uses). The new snapshot is a new plan_publication row, version + 1; the version comes from the same read the checks used and the unique index on (timeline, version) settles two adds at once: the loser's whole transaction rolls back, including its cards. The publish endpoint and its seal (E-LIVE-007) are not involved and not changed. Running it again for a job already on the day adds nothing (status already_live).
function "planner_ops/live_add_attempt" {
  input {
    json actor
    int work_item_id filters=min:1
    int timeline_id filters=min:1
    text origin? filters=trim
    text correlation_id? filters=trim
  }

  stack {
    var $actor {
      value = $input.actor
    }

    var $now_ms {
      value = now|to_int
    }

    var $out {
      value = {status: ""}
    }

    db.transaction {
      stack {
        // The current snapshot. This one read gives the version that is claimed below.
        db.query plan_publication {
          where = $db.plan_publication.timeline_id == $input.timeline_id
          return = {type: "list"}
        } as $prior

        var $cur_version {
          value = 0
        }

        var $cur_id {
          value = 0
        }

        var $gt {
          value = 0
        }

        foreach ($prior) {
          each as $p {
            var.update $gt {
              value = ($p.version > $cur_version)|to_int
            }

            var.update $cur_id {
              value = $cur_id + (($p.id - $cur_id) * $gt)
            }

            var.update $cur_version {
              value = $cur_version + (($p.version - $cur_version) * $gt)
            }
          }
        }

        precondition ($cur_version > 0) {
          error_type = "inputerror"
          error = "That day is not live yet. Publish it first. (E-DEMAND-001)"
        }

        db.get plan_publication {
          field_name = "id"
          field_value = $cur_id
        } as $cur_pub

        // The job's steps, and which of them already sit on a day.
        db.query work_task {
          where = $db.work_task.work_item_id == $input.work_item_id
          return = {type: "list"}
        } as $job_tasks

        precondition (($job_tasks|count) > 0) {
          error_type = "inputerror"
          error = "That job has no steps, so there is nothing to add to the day. (E-DEMAND-002)"
        }

        var $task_ids {
          value = [-1]
        }

        foreach ($job_tasks) {
          each as $jt {
            array.push $task_ids {
              value = $jt.id
            }
          }
        }

        db.query planner_task_work_task {
          where = $db.planner_task_work_task.work_task_id in $task_ids
          return = {type: "list"}
        } as $links

        var $linked {
          value = {}
        }

        var $slot_ids {
          value = [-1]
        }

        var $tk {
          value = ""
        }

        foreach ($links) {
          each as $l {
            var.update $tk {
              value = "k:" ~ ($l.work_task_id|to_text)
            }

            var.update $linked {
              value = $linked|set:$tk:1
            }

            array.push $slot_ids {
              value = $l.planner_task_id
            }
          }
        }

        db.query planner_task {
          where = $db.planner_task.id in $slot_ids && $db.planner_task.timeline_id != $input.timeline_id
          return = {type: "count"}
        } as $elsewhere

        precondition ($elsewhere == 0) {
          error_type = "inputerror"
          error = "Part of this job is already on another day, so it was not added. (E-DEMAND-003)"
        }

        // The rows (cards) of the job that are not on any day yet. Staged first, so the
        // only branch reads a field of the loop item.
        var $staged {
          value = []
        }

        var $hit {
          value = 0
        }

        foreach ($job_tasks) {
          each as $t {
            var.update $tk {
              value = "k:" ~ ($t.id|to_text)
            }

            var.update $hit {
              value = ($linked|get:$tk:null) ?? 0
            }

            array.push $staged {
              value = {lens_key: $t.lens_key, free: ($hit == 0)}
            }
          }
        }

        var $lens_map {
          value = {}
        }

        var $lk {
          value = ""
        }

        foreach ($staged) {
          each as $s {
            var.update $lk {
              value = "k:" ~ $s.lens_key
            }

            conditional {
              if ($s.free == true) {
                var.update $lens_map {
                  value = $lens_map|set:$lk:$s.lens_key
                }
              }
            }
          }
        }

        var $lens_list {
          value = $lens_map|values
        }

        var $cards {
          value = 0
        }

        foreach ($lens_list) {
          each as $lens {
            function.run "planner_ops/schedule_card" {
              input = {actor: $actor, work_item_id: $input.work_item_id, lens_key: $lens, timeline_id: $input.timeline_id, duration_minutes: 0, has_duration_minutes: false, assignee_agent_id: 0, correlation_id: ($input.correlation_id ?? "")}
            } as $placed

            var.update $cards {
              value = $cards + 1
            }
          }
        }

        // The day as the plan now has it. Only this job's blocks that the frozen day
        // does not already hold are taken from it.
        function.run "live/build_publication" {
          input = {timeline_id: $input.timeline_id}
        } as $live

        var $combined {
          value = []
        }

        var $old_refs {
          value = {}
        }

        var $rk {
          value = ""
        }

        var $max_seq {
          value = 0
        }

        var $old_minutes {
          value = 0
        }

        var $old_count {
          value = 0
        }

        foreach ($cur_pub.snapshot.items) {
          each as $oi {
            array.push $combined {
              value = $oi
            }

            var.update $rk {
              value = "k:" ~ $oi.item_ref
            }

            var.update $old_refs {
              value = $old_refs|set:$rk:1
            }

            var.update $gt {
              value = ($oi.seq > $max_seq)|to_int
            }

            var.update $max_seq {
              value = $max_seq + (($oi.seq - $max_seq) * $gt)
            }

            var.update $old_minutes {
              value = $old_minutes + ($oi.scheduled_minutes ?? 0)
            }

            var.update $old_count {
              value = $old_count + 1
            }
          }
        }

        function.run "live/canonical_items" {
          input = {items: $combined}
        } as $old_canon

        var $staged_live {
          value = []
        }

        var $known {
          value = 0
        }

        var $is_new {
          value = false
        }

        var $is_bad {
          value = false
        }

        foreach ($live.items) {
          each as $li {
            var.update $rk {
              value = "k:" ~ $li.item_ref
            }

            var.update $known {
              value = ($old_refs|get:$rk:null) ?? 0
            }

            var.update $is_new {
              value = ($known == 0 && $li.work_item_id == $input.work_item_id)
            }

            var.update $is_bad {
              value = ($li.assignee_agent_id == 0 || $li.assignee_has_login == false || $li.status == "needs_info")
            }

            array.push $staged_live {
              value = {item: $li, is_new: $is_new, is_bad: $is_bad}
            }
          }
        }

        var $next_seq {
          value = $max_seq
        }

        var $new_items {
          value = []
        }

        var $new_refs {
          value = []
        }

        var $bad_count {
          value = 0
        }

        var $added_minutes {
          value = 0
        }

        var $moved {
          value = null
        }

        foreach ($staged_live) {
          each as $sl {
            conditional {
              if ($sl.is_new == true) {
                var.update $next_seq {
                  value = $next_seq + 1
                }

                var.update $moved {
                  value = $sl.item|set:"seq":$next_seq
                }

                array.push $new_items {
                  value = $moved
                }

                array.push $new_refs {
                  value = $sl.item.item_ref
                }

                var.update $bad_count {
                  value = $bad_count + ($sl.is_bad|to_int)
                }

                var.update $added_minutes {
                  value = $added_minutes + ($sl.item.scheduled_minutes ?? 0)
                }
              }
            }
          }
        }

        precondition ($bad_count == 0) {
          error_type = "inputerror"
          error = "The person for that day has no login, or a step still needs information, so the job was not added. (E-DEMAND-004)"
        }

        var $new_count {
          value = $new_items|count
        }

        foreach ($new_items) {
          each as $ni {
            array.push $combined {
              value = $ni
            }
          }
        }

        function.run "live/canonical_items" {
          input = {items: $combined}
        } as $new_canon

        // The proof that planned work did not move: old text is the start of the new text.
        var $old_len {
          value = $old_canon.canonical|strlen
        }

        var $prefix {
          value = $new_canon.canonical|substr:0:$old_len
        }

        var $expected_count {
          value = $old_count + $new_count
        }

        precondition ($prefix == $old_canon.canonical && $new_canon.item_count == $expected_count) {
          error_type = "inputerror"
          error = "Adding this job would have changed work already on the day, so nothing was added. (E-DEMAND-006)"
        }

        var $next_version {
          value = $cur_version + 1
        }

        var $day_minutes {
          value = $old_minutes + $added_minutes
        }

        conditional {
          if ($new_count > 0) {
            db.add plan_publication {
              data = {
                timeline_id  : $input.timeline_id
                version      : $next_version
                published_by : $actor.user_id
                published_at : $now_ms
                snapshot     : {items: $combined, canonical_version: "publication|v3", appended_to_version: $cur_version, appended_item_refs: $new_refs}
                snapshot_hash: $new_canon.snapshot_hash
                item_count   : $expected_count
              }
            } as $publication

            db.add live_day_addition {
              data = {created_at: "now", account_id: $actor.account_id, timeline_id: $input.timeline_id, work_item_id: $input.work_item_id, plan_publication_id: $publication.id, from_version: $cur_version, to_version: $next_version, item_count: $new_count, added_minutes: $added_minutes, origin: ($input.origin ?? ""), added_by_user_id: $actor.user_id}
            } as $addition

            var.update $out {
              value = {status: "added", timeline_id: $input.timeline_id, publication_id: $publication.id, from_version: $cur_version, version: $next_version, added_item_refs: $new_refs, added_count: $new_count, added_minutes: $added_minutes, day_total_minutes: $day_minutes, item_count: $expected_count, snapshot_hash: $new_canon.snapshot_hash}
            }
          }

          else {
            var.update $out {
              value = {status: "already_live", timeline_id: $input.timeline_id, publication_id: $cur_id, from_version: $cur_version, version: $cur_version, added_item_refs: [], added_count: 0, added_minutes: 0, day_total_minutes: $old_minutes, item_count: $old_count, snapshot_hash: $cur_pub.snapshot_hash}
            }
          }
        }
      }
    }
  }

  response = $out
}
