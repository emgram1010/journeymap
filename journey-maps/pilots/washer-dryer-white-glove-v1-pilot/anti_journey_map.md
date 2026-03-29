## White-Glove Washer/Dryer Anti-Journey Map

### Purpose
Map where the happy path breaks in washer/dryer white-glove delivery, what changes the correct response, who should decide, and what downstream damage occurs if the issue is mishandled.

### Draft status
This is the **first domain-specific anti-journey example** built from the washer/dryer draft. Stages 1-2 are strongest; stages 3-8 are still pilot-grade and should be validated with follow-up examples.

---

## 1) Anti-Journey Header

- **Scenario:** Washer/dryer white-glove delivery from order release through post-install issue resolution
- **Anti-Journey Map Name:** White-Glove Washer/Dryer Delivery - Anti-Journey v1-draft
- **Based On Journey Map:** `journey-maps/drafts/washer-dryer-white-glove-v1-draft.md` and workbook pilot CSVs in this folder
- **Primary Expert Role Interviewed:** Javier - Operations Design Lead
- **Version:** v1-draft
- **Confidence Level:** Medium for stages 1-2; low-to-medium for stages 3-8

---

## 2) Breakpoint Matrix (Executive View)

| Stage | Breakpoint / Failure Mode | Trigger | Key Variable | Correct Decision | Escalation Trigger | Downstream Damage |
|---|---|---|---|---|---|---|
| Stage 1: Order Review & Appointment Confirmation | Order looks schedulable but installability is actually wrong | Service attributes conflict with install reality | Minor data cleanup vs real serviceability problem | Hold/correct scheduling until scope is verified | Ambiguity about what can actually be delivered or installed | Bad appointment; failed install; wasted route capacity |
| Stage 2: Pre-Delivery Qualification & Site Readiness Check | Site is not actually ready | Photos/specs/access/hookup reality do not support the install | Fixable remotely before dispatch vs true same-day no-go | Resolve remotely if possible; otherwise reschedule/escalate before dispatch | Safety; code; or cost exceeds front-line authority | Crew arrives to a non-installable site; route waste; rework |
| Stage 3: Route Planning & Inventory/Load Verification | Route/load plan is operationally wrong | Shortage; missing kit; or unrealistic route load appears | Absorbable with resequencing/substitution vs full replan | Rebuild the route if needed; do not force a known bad stop | Conflict or shortage exceeds dispatch authority | Failed stop; late route; cascading service failure |
| Stage 4: Arrival & Home Access Confirmation | Field no-go at the door | Actual access/site conditions differ from readiness notes | Safe/manageable mismatch vs true no-go | Proceed only if safe and in scope; otherwise stop and escalate | Crew cannot safely proceed | Injury; damage; unauthorized work; route disruption |
| Stage 5: Appliance Removal | Removal becomes unsafe or disputed | Shutoff; scope; or movement path is not what the crew expected | Safe within crew authority vs requires escalation | Do not force removal when safety or scope is unclear | Damage; safety; or scope dispute exceeds crew authority | Leak; damage; complaint; failed install |
| Stage 6: Install & Utility Connection | Standard install turns non-standard | Code; safety; utility; or product issue appears during hookup | Remediable within field authority vs technical/management escalation | Stop standard install and escalate when authority boundary is crossed | Code; safety; or product issue appears | Unsafe install; liability; callback; customer harm |
| Stage 7: Testing & Customer Sign-Off | Closeout fails | Unit fails test or customer disputes quality/damage/completeness | Fixable immediately vs needs handoff with proof | Resolve now only if safe/clear; otherwise capture proof and escalate | Dispute; damage; or failure cannot be resolved in stop | Weak evidence trail; repeat visit; dispute vulnerability |
| Stage 8: Post-Install Issue Resolution | Recovery is misrouted | Complaint/defect enters the system without clear ownership | Severity/cost and true owner of the issue | Route to the right owner on the first handoff | Severity or cost exceeds front-line authority | Long open cases; duplicated work; angry customer |

---

## 3) Breakpoint Detail Template (Filled For Major Exceptions)

### Breakpoint: False Installability At Intake
- **Stage:** Stage 1
- **What breaks:** The order is treated as deliverable/installable when the data does not support that assumption.
- **Trigger / detection signal:** Service attributes; notes; or install requirements conflict with the reality of what can be installed.
- **Key variable that changes the right answer:** Whether the issue is a harmless data cleanup or a true serviceability conflict.
- **Incorrect but tempting action:** Keep the appointment and hope the field team sorts it out later.
- **Correct decision:** Hold or correct scheduling until serviceability is verified.
- **Primary owner / decision authority:** Scheduling
- **Escalation owner / receiving role:** Operations management
- **Customer communication needed:** Explain that the order needs verification before a field-ready appointment is locked.
- **Documentation / proof required:** Corrected service attributes; contact outcomes; OMS/order notes.
- **Immediate consequence if mishandled:** Bad appointment and false promise to the customer.
- **Downstream damage / cascade risk:** Failed install; wasted route capacity; distrust before the crew even arrives.
- **Resolution Outcome A:** The issue is corrected and the job moves to readiness review.
- **Resolution Outcome B:** The job is re-scoped; rescheduled; or rejected as sold incorrectly.
- **Does this create a sub-journey?:** Yes - escalated serviceability review before scheduling.

#### Hidden Knowledge
- What outsiders usually miss: Scheduling is acting as an operational risk screen, not just calendar admin.
- What hidden judgment matters most: Distinguishing between harmless cleanup and true installability conflict.
- What a novice gets wrong here: Treating incomplete data as a minor inconvenience instead of a route-killing input failure.

#### Evidence / Open Questions
- Direct expert quote or example: "Decision authority is usually scheduling, with operations management stepping in when the order data conflicts with install reality."
- Open question / ambiguity to validate: What are the top three real stage-1 failures Javier sees most often?

### Breakpoint: Readiness Gap Missed Before Dispatch
- **Stage:** Stage 2
- **What breaks:** The site appears ready on paper but is not actually installable.
- **Trigger / detection signal:** Missing photos; wrong specs; blocked valves; undisclosed access constraints; customer prep gap.
- **Key variable that changes the right answer:** Whether the gap can be solved remotely before dispatch or requires rescheduling.
- **Incorrect but tempting action:** Push the job forward because the route is already being built.
- **Correct decision:** Resolve remotely if possible; otherwise stop the job before the truck leaves.
- **Primary owner / decision authority:** Pre-install support
- **Escalation owner / receiving role:** Operations management / dispatch depending on route impact
- **Customer communication needed:** Tell the customer exactly what is missing; what must be fixed; and whether timing changes.
- **Documentation / proof required:** Photos; notes; reason codes; customer acknowledgment.
- **Immediate consequence if mishandled:** Crew arrives to a site they cannot complete.
- **Downstream damage / cascade risk:** Failed install; route waste; rework; lower customer trust.
- **Resolution Outcome A:** Customer resolves the gap and the job stays on route.
- **Resolution Outcome B:** Job is rescheduled or moved into a different sub-journey.
- **Does this create a sub-journey?:** Yes - readiness recovery / reschedule path.

#### Hidden Knowledge
- What outsiders usually miss: Most failures are created before the truck leaves, not at the door.
- What hidden judgment matters most: Knowing which prep gaps are fixable remotely and which are true no-go conditions.
- What a novice gets wrong here: Treating all site issues as equal instead of ranking them by safety and installability.

#### Evidence / Open Questions
- Direct expert quote or example: "Most failures are created before the truck leaves, not at the door."
- Open question / ambiguity to validate: Which readiness prompts or wording most reliably produce usable customer info?

### Breakpoint: Route / Load Plan Is Wrong
- **Stage:** Stage 3
- **What breaks:** Dispatch and load verification reveal that the planned route cannot be executed as promised.
- **Trigger / detection signal:** Shortage; missing kit; accessory mismatch; unrealistic stop-time assumptions; critical readiness notes missing from manifest decisions.
- **Key variable that changes the right answer:** Whether the issue can be absorbed with resequencing/substitution or requires a route rebuild.
- **Incorrect but tempting action:** Leave the route intact and hope the crew improvises.
- **Correct decision:** Replan when necessary and avoid knowingly sending a bad stop into the field.
- **Primary owner / decision authority:** Dispatch / route planning
- **Escalation owner / receiving role:** Operations management
- **Customer communication needed:** Inform the customer if timing or viability changes materially.
- **Documentation / proof required:** Load verification; shortage record; resequencing notes; manifest update.
- **Immediate consequence if mishandled:** Same-day failure becomes locked into the route.
- **Downstream damage / cascade risk:** Failed stop; late arrivals; compressed installs; cascading service failure.
- **Resolution Outcome A:** Resequencing or substitution saves the day.
- **Resolution Outcome B:** Stop is removed/rebooked and the route is rebuilt.
- **Does this create a sub-journey?:** Yes - replan/reload workflow.

#### Hidden Knowledge
- What outsiders usually miss: A route can be operationally wrong even if optimization software says it fits.
- What hidden judgment matters most: Balancing promised windows against actual service complexity and crew reality.
- What a novice gets wrong here: Treating every job as an equal-duration box.

#### Evidence / Open Questions
- Direct expert quote or example: "The objective is to build a feasible route and make sure the correct product, parts, and tools are loaded."
- Open question / ambiguity to validate: What are Javier's top three real stage-3 failures and how often do they force route rebuilds?

### Breakpoint: Unsafe / Non-Standard Install During Hookup
- **Stage:** Stage 6
- **What breaks:** The install stops being standard because code; safety; product; or utility reality conflicts with the expected job.
- **Trigger / detection signal:** Code violation; safety issue; defective product; missing install kit; utility mismatch.
- **Key variable that changes the right answer:** Whether the issue is safely remediable within field authority.
- **Incorrect but tempting action:** Force completion because the route is behind or the customer expects it.
- **Correct decision:** Stop standard install work and escalate once the authority boundary is crossed.
- **Primary owner / decision authority:** Installer or crew lead
- **Escalation owner / receiving role:** Technical support or operations management
- **Customer communication needed:** Tell the customer what cannot be completed safely or to code and what the next step is.
- **Documentation / proof required:** Photos; checklist; specific defect or code notes.
- **Immediate consequence if mishandled:** Unsafe or non-compliant install.
- **Downstream damage / cascade risk:** Liability; callback; customer harm; costly recovery.
- **Resolution Outcome A:** Issue is resolved inside allowed field authority and testing proceeds.
- **Resolution Outcome B:** Job turns into a revisit; no-go; or technical escalation workflow.
- **Does this create a sub-journey?:** Yes - technical support / revisit workflow.

#### Hidden Knowledge
- What outsiders usually miss: "Connected" is not the same as safe and to code.
- What hidden judgment matters most: Knowing exactly where field authority stops.
- What a novice gets wrong here: Confusing customer pressure with permission to improvise.

#### Evidence / Open Questions
- Direct expert quote or example: "The installer or crew lead escalates to technical support or management when code, safety, or product issues appear."
- Open question / ambiguity to validate: Which install problems always force a no-go versus a workaround?

### Breakpoint: Post-Install Issue Misrouted
- **Stage:** Stage 8
- **What breaks:** A complaint or defect enters the post-install flow but is given to the wrong owner.
- **Trigger / detection signal:** Severity; cost; evidence quality; and issue type are unclear at intake.
- **Key variable that changes the right answer:** Whether the issue is best handled by customer care; field service; or management.
- **Incorrect but tempting action:** Treat every complaint as the same workflow and forward it without real classification.
- **Correct decision:** Classify severity correctly and route to the right owner on the first handoff.
- **Primary owner / decision authority:** Customer care / field service / operations management depending on severity and cost
- **Escalation owner / receiving role:** Operations management for high-severity or high-cost cases
- **Customer communication needed:** Confirm who owns the case; what happens next; and expected timing.
- **Documentation / proof required:** Install notes; photos; reason codes; service history; owner and promised timeline.
- **Immediate consequence if mishandled:** Delayed remedy and customer confusion.
- **Downstream damage / cascade risk:** Duplicated work; long open cases; poor recovery experience; avoidable cost.
- **Resolution Outcome A:** Correct owner resolves the issue quickly with strong evidence.
- **Resolution Outcome B:** Issue escalates into claim/recovery workflow because severity or cost exceeds front-line authority.
- **Does this create a sub-journey?:** Yes - revisit/rework or claim-resolution workflow.

#### Hidden Knowledge
- What outsiders usually miss: Fast ownership is often more important to the customer than instant resolution.
- What hidden judgment matters most: Matching issue severity to the right owner on the first handoff.
- What a novice gets wrong here: Treating all complaints as the same operational case.

#### Evidence / Open Questions
- Direct expert quote or example: "Decision authority shifts between customer care, field service, and operations management based on severity and cost."
- Open question / ambiguity to validate: What are the exact routing thresholds by severity; cost; and issue type?

---

## 4) Cross-Breakpoint Synthesis

### Highest-Risk Breakpoints
- Readiness gap missed before dispatch
- Unsafe / non-standard install during hookup
- Post-install issue misrouted

### Variables That Most Often Change The Right Answer
- Can this be corrected remotely before dispatch?
- Can the crew still complete safely within scope and authority?
- How severe and costly is the issue?

### Escalations That Need Clear Rules
- Serviceability / intake escalation
- Safety / code escalation
- Route-breaking shortage or infeasibility escalation
- Damage / complaint recovery escalation

### Failure Patterns That Repeat Across Stages
- Upstream bad data creates downstream field failure.
- The wrong person holds a decision too long.
- Weak documentation turns a fixable problem into a long recovery loop.

### Follow-Up Questions
- What are the most frequent real examples for stages 3-8?
- Which evidence items are truly non-negotiable before handoff to the next owner?
- What exact thresholds move an issue from front-line handling to management recovery?

---

## 5) Quality Check Before Finalizing

- [x] each major breakpoint names a real trigger
- [x] each breakpoint includes the variable that changes the right answer
- [x] the correct decision is explicit
- [x] escalation authority is explicit where ambiguity matters
- [x] downstream damage is concrete
- [x] sub-journeys are called out where they exist
- [~] all major breakpoints are backed by fully validated expert examples
- [x] unclear points are captured as open questions
