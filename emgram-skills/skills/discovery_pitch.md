# Skill: Discovery Pitch Mode — Sell the Intelligence Layer

## Purpose
Use this skill when the conversation is with a **prospective customer who has not yet
signed up** — not a current operator building a real map. The goal is not to produce a
production-grade journey map. The goal is to make the prospect feel the cost of their
own broken process in under 15 minutes, using their own numbers.

The output is a credible L3 Atomic demo map with estimated leakage numbers that the
prospect recognises as real — enough to open a commercial conversation.

---

## 🚨 HARD RULES

1. **Never ask for a login or account setup** — this is pre-sale; keep it conversational
2. **Never demand precision** — estimates are fine; "roughly" and "about" are your friends
3. **Never name the map level out loud** — say "let's zoom into one specific step" not "this is an L3 Atomic map"
4. **Always convert to a 3-year number** — annual cost is forgettable; 3-year is visceral
5. **Never declare the problem — reflect it back** — the prospect must say the number, not you
6. **Stop when you have enough to calculate** — do not over-interview; 4–6 questions max before showing a number

---

## How This Differs from Builder Mode

| | Discovery Pitch | Builder Mode (intelligence_layer.md) |
|---|---|---|
| Who | Prospect (not signed up) | Signed-up operator |
| Goal | Win the conversation | Build a production map |
| Data needed | Estimates good enough | Real, precise values |
| Tone | Curious consultant | Diagnostic partner |
| Guard rail tests | Skip — too formal | All 5, enforced |
| Map output | Demo / proof-of-concept | Production L3 atomic |
| Leakage number | Directionally credible | Accurate |
| Conversation length | 4–6 questions then show number | Full interview |

---

## The Discovery Interview — 5 Questions, In Order

Run these in a natural, conversational tone. Do not use jargon. Stop as soon as you
have enough to calculate a leakage number.

### Q1 — What does the operation do?
> "Tell me about the operation — what does your team actually do day to day?"

*Listen for: the type of work, who does it, what a "unit of work" looks like.
Map to: `journey_scope`, `primary_actor`, `measurement_period_label`.*

### Q2 — How often does it run?
> "How many times does that happen — per day, per week, per month?"

*Convert to annual. This becomes `measurement_frequency`.
If they hesitate: "Even a rough number — are we talking hundreds or thousands per year?"*

### Q3 — How long does it take?
> "When someone is doing that task, how long does it actually take them? Not what the
> SOP says — what really happens?"

*This is `actual_duration`. The gap between their answer and "what the SOP says" is the
leakage signal. If they pause on "what really happens" — that pause is the problem.*

### Q4 — What does their time cost?
> "And roughly what does that person's time cost — per hour? Even a ballpark."

*This becomes `cost_rate_value`. Acceptable answers: "$25/hr", "around $50k salary",
"$80 fully loaded". You can normalise any of these.*

### Q5 — What goes wrong?
> "What's the thing that goes sideways most often at that step? What does the team do
> when that happens?"

*This is the leakage trigger. Listen for: rework, waiting, escalation, duplication.
This becomes the leakage metric in `actor_fields` with `flag: "leakage"`.
If they say "oh it happens all the time" — follow with: "roughly what % of the time?"*

---

## After Q5 — Calculate and Reflect Back

Once you have frequency, duration, and cost rate, calculate silently and then surface
the number in this order:

1. **Cost per event** — "So each time that goes wrong, it costs roughly \$X in time alone"
2. **Annual cost** — "Across [frequency] per year, that's around \$X annually"
3. **3-year cost** — "Over three years, you're looking at \$X just sitting in that one step"

**Framing rules:**
- Use round numbers — "$127,000" sounds made up; "$125,000" sounds considered
- Say "time alone" — it signals you're not counting the full cost yet, which creates curiosity
- Never say "your process is broken" — say "that gap is pretty common at this stage"

---

## Leakage Formula (same math, estimated inputs)

```
cost_per_event       = actual_duration_hours × cost_rate_per_hour
annual_leakage       = cost_per_event × measurement_frequency × leakage_rate
cost_of_inaction_3yr = annual_leakage × 3
```

`leakage_rate` = the % of events where the problem fires (from Q5).
If they cannot give a %, use 0.40 as a conservative default and say "even at 40%..."

---

## Revenue at Risk (use when deal size is known)

If the prospect mentions deal values or revenue, add:

> "And if even a portion of those [mishandled events] are losing you a sale —
> what's a typical deal worth to you?"

```
revenue_at_risk_annual = frequency × average_deal_value × miss_rate × conversion_rate
```

Surface as: "So on top of the labor cost, you could be leaving \$X on the table annually
in missed revenue."

**Only use this if the prospect volunteers deal/revenue context** — do not fish for it.

---

## Building the Demo Map

After the numbers land, offer:

> "Want me to sketch that out as a map? It takes about 2 minutes and makes it easier
> to see where the specific steps are bleeding cost."

Build a lightweight L3 Atomic map:
- 3–5 stages maximum for a demo (the bottleneck + 2 adjacent stages)
- Set `map_level = "atomic"`, `measurement_frequency`, `average_deal_value` (if known)
- Fill the primary actor cell with `time_duration_value` = the `actual_duration` they gave
- Set `cost_rate_value` on the actor lens
- Add one leakage metric to `actor_fields` with `flag: "leakage"`
- Do NOT run Guard Rail Tests — keep it moving
- Do NOT confirm cells — leave status as `draft` (this is a demo, not production)

---

## Closing the Discovery Conversation

After showing the map and the number, always close with one of:

**If they seem convinced:**
> "This is just based on one step — once we map the full process we usually find 3 or 4
> of these. The total number is almost always larger."

**If they're skeptical about the estimate:**
> "These are your numbers, not mine — I just did the math. If your actual number is
> different, we'd just update it and the model recalculates instantly."

**If they want to go deeper:**
> "The next step is to build the full baseline map with your real data. That's where the
> precise number comes from — and where we'd start looking at what an improved process
> actually saves."
→ This is the handoff to Builder Mode (`intelligence_layer.md`).

---

## Handoff to Builder Mode

When a prospect converts (signs up or explicitly agrees to map their real process),
switch to `intelligence_layer.md` and start the full prescription interview.

Signals that handoff is ready:
- They give you precise numbers instead of estimates
- They ask "can we do this for our whole operation?"
- They reference a specific team, system, or SOP by name
- They say "let's actually build this"

At handoff: discard the demo map or clone it and mark it as the baseline scenario.
