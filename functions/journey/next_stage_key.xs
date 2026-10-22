// ORD-1 (US-ORD-1-01) — The key and display_order for a new stage in a map.
//
// THE ONE PLACE A STAGE KEY IS MINTED. Every path that adds a stage to an
// existing map calls this: journey_stage/add and the AI tool scaffold_map.
// Before ORD-1 each minted its own key as "s" + (max display_order + 1) —
// or, in scaffold_map, count + 1, which could already collide after a
// remove — so a key was a copy of a position. The moment anything renumbers
// display_order (resequence, ORD-1 story 02) the next add would mint a key
// that already exists, and a key is identity: primary_actor_lens holds a
// lens KEY as text, and work_task is identified by (stage_key, lens_key).
//
// The rule: the new number is one more than the largest of
//   - every existing key of the exact shape "s<digits>", and
//   - every existing display_order.
// Including display_order keeps the answer identical to the old formula on
// every map that has never been reordered (keys and orders were equal on
// all 201 stages when this shipped). Any value can only push the number UP,
// so the result can never equal an existing "s<N>" key: N is in the set the
// max was taken over. A key of any other shape cannot equal "s<digits>".
//
// What this does NOT prevent: two requests adding to the same map at the
// same instant both read the same rows and mint the same key. A check
// before the insert cannot catch that (both see no clash); only a unique
// index on (journey_map, key) can. Same exposure as before ORD-1.
//
// No conditional inside the loop (CLAUDE.md): the shape test is turned
// into 0/1 with to_int and multiplied in, so a non-matching key adds 0.
// Verified live on real data with scratch/ord1_key_census before shipping.
function "journey/next_stage_key" {
  input {
    int journey_map_id filters=min:1
  }

  stack {
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.journey_map_id
      return = {type: "list"}
    } as $rows

    var $numbers {
      value = [0]
    }

    var $orders {
      value = [0]
    }

    foreach ($rows) {
      each as $r {
        var $digits {
          value = ("/[^0-9]/"|regex_replace:"":$r.key)|to_int
        }

        var $is_shape {
          value = ("/^s[0-9]+$/"|regex_matches:$r.key)|to_int
        }

        var $order {
          value = $r.display_order|to_int
        }

        array.push $numbers {
          value = $digits * $is_shape
        }

        array.push $numbers {
          value = $order
        }

        array.push $orders {
          value = $order
        }
      }
    }

    var $next_number {
      value = ($numbers|max) + 1
    }

    var $next_order {
      value = ($orders|max) + 1
    }

    var $minted_key {
      value = "s" ~ ($next_number|to_text)
    }
  }

  response = {
    key           : $minted_key
    number        : $next_number
    display_order : $next_order
    existing_count: $rows|count
  }
}
