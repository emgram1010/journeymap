## White-Glove Washer/Dryer Delivery Journey Map

**Template role:** This file is the first domain-specific pilot/example. The reusable cross-domain templates live in `workspace/templates/journey-map-blueprint-template.md` and `workspace/templates/anti-journey-map-template.md`.

### 1) Journey Header

- **Scenario:** Washer/dryer white-glove delivery from order release through installation completion and post-install issue resolution
- **Journey Map Name:** White-Glove Washer/Dryer Delivery - 8 Stage Expert Draft
- **Scope Boundary:** Starts when the order is released from sales/ecommerce into operations; ends when post-install issues are resolved or formally handed off with owner and timeline
- **Primary Expert Role Interviewed:** Javier - Operations Design Lead
- **Other Roles Mentioned:** Scheduling, pre-install support, dispatch, route planning, crew lead, installer, operations management, customer care, field service
- **Source Interview Date:** 2026-03-22 saved transcript, plus 2026-03-23 live continuation for stages 3-8 definitions
- **Map Owner:** Emgram1010
- **Version:** v1-draft
- **Confidence Level:** Medium for stages 1-2; low-to-medium for stages 3-8 pending full pain-point follow-up

**Evidence note:** This draft uses the saved Formless transcript as the primary source. Where the saved transcript was incomplete, stage definitions were supplemented with the continued live interview and the archived source table in `journey-maps/drafts/washer-dryer-white-glove-source-table.md`. Any non-directly validated content is marked as draft, hypothesis, or open question.

---

### 2) Stage Grid (Executive View)

| Lens | Stage 1: Order Review & Appointment Confirmation | Stage 2: Pre-Delivery Qualification & Site Readiness | Stage 3: Route Planning & Inventory/Load Verification | Stage 4: Arrival & Home Access Confirmation | Stage 5: Appliance Removal | Stage 6: Install & Utility Connection | Stage 7: Testing & Customer Sign-Off | Stage 8: Post-Install Issue Resolution |
|---|---|---|---|---|---|---|---|---|
| Description | Confirm order is deliverable and schedule correctly. | Verify site, hookups, access path, and specs match install. | Build feasible route and verify product, parts, and tools are loaded. | Confirm actual site conditions and safe access on arrival. | Remove old unit safely if haul-away is included. | Place, connect, and level the new unit to code. | Test unit, brief customer, and capture sign-off. | Resolve defects, damage, incomplete work, or complaints. |
| Notifications | Order confirmation and appointment confirmation. | Prep checklist, readiness requests, timing changes if exceptions arise. | Mostly internal. Route/crew prep. | Arrival call or 30-min heads-up. | Confirm haul-away scope if needed. | Usually no automated notification during install. | Completion message, POD, photos, customer briefing. | Follow-up, case updates, resolution timeline. |
| Customer | Wants clear date/time and confidence the order is right. | Must provide photos, site details, and readiness info. | Usually unaware unless timing shifts. | Must be present and provide access. | Wants safe removal without damage or scope surprises. | Watches install quality and asks questions. | Wants proof unit works before crew leaves. | Wants fast ownership, clarity, and remedy. |
| Scheduling / Pre-Install | Scheduling owns routine decisions; ops steps in when order data conflicts with install reality. | Pre-install support owns readiness check; ops escalates conflicts. | Feeds confirmed notes into route planning. | Usually passive unless field finds mismatch. | Not primary owner. | Not primary owner. | Not primary owner. | May help with records, not primary owner. |
| Dispatch / Route Planning | Limited involvement. | Needs notice when readiness changes route feasibility. | Owns route assignment, crew capacity, and shortage/conflict handling. | Supports field if site conditions conflict with plan. | Supports escalations affecting route timing. | Supports escalations affecting route timing. | Supports disputes or failures that affect downstream stops. | Supports field service handoff if revisit is needed. |
| Field Crew / Installer | Not yet active. | Not yet on site, but their later success depends on this stage. | Needs correct product, parts, tools, and notes. | Crew lead owns go/no-go for entry and install. | Crew lead owns safe removal. | Installer or crew lead owns connection work; escalates code/safety/product issues. | Crew lead owns testing, briefing, and sign-off capture. | Field service may own remedy depending on severity. |
| Systems / Tools | OMS, scheduling tools, CRM/order record. | Photos, notes, readiness checklist, specs, utility requirements. | Dispatch dashboard, route planning tools, inventory/load checks. | Order packet, site notes, customer contact details. | Haul-away request, safety checklist, disposal rules. | Product specs, install kit, tools, code requirements. | Test checklist, photos, POD/signature tools. | Case notes, complaint details, reason codes, service history. |
| Metrics | Schedule confirmation speed; order data accuracy. | Readiness verification rate; avoided failed installs; exception detection before dispatch. | Route feasibility; load accuracy; shortage/conflict rate. | First-attempt access success; dwell-time variance. | Safe haul-away completion; damage incidents. | Install completion rate; code/safety escalations; install time. | Test pass rate; sign-off capture; damage/dispute rate. | Resolution time; repeat visits; complaint recovery outcomes. |

---

### 3) Stage Detail Template

### Stage 1: Order Review & Appointment Confirmation
- **Objective:** Confirm the order is deliverable and the customer is scheduled correctly.
- **Start Trigger:** Order is released from sales or ecommerce into operations.
- **Completion Condition:** Appointment is confirmed and the order is cleared for pre-delivery review.
- **Required Inputs:** SKU details, customer contact info, install requirements, haul-away request, address data.
- **Primary Owner / Decision Authority:** Scheduling; operations management steps in when order data conflicts with install reality.
- **Other Roles Involved:** Sales/ecommerce handoff, operations management.
- **Systems / Tools Used:** OMS, scheduling workflow, customer contact records.
- **Happy Path Summary:** The order enters ops cleanly, required service attributes are present, the customer is contacted successfully, and the order is scheduled without downstream install conflict.

#### Customer Experience
- What the customer sees: Confirmation that the order exists and that an appointment is being set.
- What the customer is likely feeling / worrying about: Whether timing is real, whether install/haul-away was captured correctly, and whether someone will arrive prepared.
- What the customer must do: Confirm availability and provide accurate contact/location details.
- What the customer is told: Delivery date/window and any preparation expectations.

#### Pain Points / Failure Modes
1. **Pain Point:** Order data conflicts with install reality. *(Directly implied by expert authority note.)*
   - Key variable that changes the correct response: Whether the conflict is minor and correctable in scheduling or indicates a real serviceability problem.
   - Correct response depends on: Data completeness, ability to verify quickly, and whether field execution would fail if left unresolved.
   - Cascade risk if mishandled: Bad appointments, failed installs, wasted route capacity, and customer distrust.
2. **Pain Point:** Install requirements or haul-away scope are missing or miscoded. *(Draft hypothesis to validate.)*
   - Key variable that changes the correct response: Whether the missing detail changes crew type, parts, or appointment length.
   - Correct response depends on: Service-level accuracy and ability to correct before pre-delivery review.
   - Cascade risk if mishandled: Wrong crew/tools, incomplete visit, reschedule.
3. **Pain Point:** Address or customer contact data is incomplete or wrong. *(Draft hypothesis to validate.)*
   - Key variable that changes the correct response: Whether the issue can be corrected before route planning.
   - Correct response depends on: Reachability, address validation, and timing pressure.
   - Cascade risk if mishandled: Routing errors, missed contact, failed first attempt.

#### Exceptions
- **Common exceptions:** Customer unavailable for confirmation; missing service attributes; conflicting order notes.
- **Rare but high-risk exceptions:** Order sold as installable when site/service is actually out of scope.
- **Separate sub-journeys created by this stage:** Escalated serviceability review before scheduling.

#### Communication / Documentation / Escalation
- **Who must be informed:** Customer on confirmed timing; ops management when order data conflicts with install reality.
- **What must be documented:** Corrected service attributes, contact outcomes, schedule commitments.
- **What system record must be updated:** OMS/order record and scheduling record.
- **Escalation trigger:** Order data creates ambiguity about what can actually be delivered or installed.
- **Proof / evidence required:** Updated notes and corrected order attributes.

#### Metrics
- **Primary KPIs:** Time to schedule confirmation; order data accuracy.
- **Failure indicators:** High reschedule rate traced to bad intake; repeated downstream clarification.

#### Hidden Knowledge
- **What outsiders usually miss:** A bad order record can make the rest of the journey fail before the field team ever sees it.
- **What hidden judgment matters most:** Distinguishing between a harmless data cleanup and a true installability conflict.
- **What a novice gets wrong here:** Treating scheduling as administrative instead of operational risk screening.

#### Evidence / Open Questions
- **Direct expert quote or example:** “Decision authority is usually scheduling, with operations management stepping in when the order data conflicts with install reality.”
- **Open question / ambiguity to validate:** What are the top three real stage-1 failures Javier sees most often?

---

### Stage 2: Pre-Delivery Qualification & Site Readiness Check
- **Objective:** Verify the home, hookups, access path, and product specs match the install.
- **Start Trigger:** Appointment confirmation.
- **Completion Condition:** Readiness is verified or exceptions are flagged.
- **Required Inputs:** Order details, specs, photos, customer notes, utility requirements.
- **Primary Owner / Decision Authority:** Pre-install support, with operations escalation for conflicts.
- **Other Roles Involved:** Dispatch, operations management, customer.
- **Systems / Tools Used:** Photos, notes, readiness checklist, specs, utility requirements, reason codes.
- **Happy Path Summary:** The team verifies the site remotely, identifies no blocking issues, captures the right notes, and passes a clean job forward to route planning.

#### Customer Experience
- What the customer sees: Requests for photos, prep confirmation, and sometimes clarification about hookups, access, or missing parts.
- What the customer is likely feeling / worrying about: Whether they have done enough prep and whether the crew will arrive able to finish.
- What the customer must do: Provide accurate photos/details and complete prep requirements.
- What the customer is told: What must be ready, what changed if the site is not ready, and whether timing must move.

#### Pain Points / Failure Modes
1. **Pain Point:** Wrong appliance specs or missing customer photos.
   - Key variable that changes the correct response: Whether the mismatch can be resolved before dispatch with better photos, spec confirmation, or a product swap.
   - Correct response depends on: Speed of verification and whether the corrected information changes crew, tools, or product.
   - Cascade risk if mishandled: Wrong crew, tools, or product sent; failed delivery; route waste; rescheduling; lower customer trust.
2. **Pain Point:** The customer says hookups or clearance exist when they do not.
   - Key variable that changes the correct response: Whether the gap can be fixed by simple customer prep or whether it makes install impossible that day.
   - Correct response depends on: What the customer can remediate remotely before dispatch.
   - Cascade risk if mishandled: Crew arrives to a non-installable site, loses route capacity, triggers rework, and frustrates the customer.
3. **Pain Point:** Access constraints like stairs, tight turns, or door width are discovered too late.
   - Key variable that changes the correct response: Whether the crew can still complete safely with different equipment, added labor, or a revised plan.
   - Correct response depends on: Safety feasibility, equipment availability, and whether the route can absorb the change.
   - Cascade risk if mishandled: Injury, property damage, failed install, and disruption to every remaining stop on the route.

#### Exceptions
- **Common exceptions:** Stacked units not disclosed, blocked shutoff valves, customers missing required parts.
- **Rare but high-risk exceptions:** Gas leak signs, unsafe wiring, water damage.
- **Separate sub-journeys created by this stage:** Permit-required installs, hoist jobs, builder-site deliveries.

#### Communication / Documentation / Escalation
- **Who must be informed:** Customer when readiness or timing changes; dispatch when route feasibility changes; management when safety, damage, or recovery risk appears.
- **What must be documented:** Photos, notes, reason codes, customer acknowledgment.
- **What system record must be updated:** Readiness status, exception notes, route-feasibility flags.
- **Escalation trigger:** Safety, code, or cost decisions exceed field authority.
- **Proof / evidence required:** Photos, notes, reason codes, customer acknowledgment.

#### Metrics
- **Primary KPIs:** Readiness verification rate; exception catch rate before dispatch; avoided failed installs.
- **Failure indicators:** High day-of-install failures caused by bad remote qualification; repeated route loss from preventable site issues.

#### Hidden Knowledge
- **What outsiders usually miss:** Most failures are created before the truck leaves, not at the door.
- **What hidden judgment matters most:** Deciding when a readiness gap can be solved remotely versus when it requires rescheduling or escalation.
- **What a novice gets wrong here:** Assuming all site issues are equivalent instead of separating fixable prep gaps from true no-go conditions.

#### Evidence / Open Questions
- **Direct expert quote or example:** “Most failures are created before the truck leaves, not at the door.”
- **Open question / ambiguity to validate:** What wording or checklist items most reliably get customers to provide usable readiness info?

---

### Stage 3: Route Planning & Inventory/Load Verification
- **Objective:** Build a feasible route and make sure the correct product, parts, and tools are loaded.
- **Start Trigger:** Site readiness is confirmed or exceptions are routed.
- **Completion Condition:** Route is assigned and the load is verified against the jobs.
- **Required Inputs:** Confirmed install notes, crew capacity, geography, inventory availability, accessories, service windows.
- **Primary Owner / Decision Authority:** Dispatch and route planning, with operations management handling conflicts or shortages.
- **Other Roles Involved:** Warehouse/load team, pre-install support, crew lead.
- **Systems / Tools Used:** Dispatch dashboard, route planning tools, inventory/load verification.
- **Happy Path Summary:** Dispatch builds a route that matches promised windows, crew capability, and actual inventory/tool needs.

#### Customer Experience
- What the customer sees: Usually nothing unless the route affects ETA or appointment commitments.
- What the customer is likely feeling / worrying about: Mostly waiting for the promised service window.
- What the customer must do: Remain reachable if timing changes.
- What the customer is told: Updated ETA or service window if needed.

#### Pain Points / Failure Modes
1. **Pain Point:** Product, part, or accessory shortage discovered at load verification. *(Draft from stage definition + baseline journey.)*
   - Key variable that changes the correct response: Whether the shortage has a same-day substitute or forces replan.
   - Correct response depends on: Inventory flexibility and route slack.
   - Cascade risk if mishandled: Failed stop, wasted crew time, customer disappointment, route disruption.
2. **Pain Point:** Route looks feasible on paper but not with actual service times or site complexity. *(Draft.)*
   - Key variable that changes the correct response: Whether the overload is absorbable with resequencing or requires route reduction.
   - Correct response depends on: Crew capacity, geography, and stop duration realism.
   - Cascade risk if mishandled: Late arrivals, missed windows, compressed installs, cascading service failure.
3. **Pain Point:** Install notes from readiness review do not make it into dispatch/load decisions. *(Draft.)*
   - Key variable that changes the correct response: Whether critical notes change tools, labor, or stop sequencing.
   - Correct response depends on: Quality of handoff between readiness and dispatch.
   - Cascade risk if mishandled: Wrong tools/crew, unsafe field improvisation, failed completion.

#### Exceptions
- **Common exceptions:** Short inventory, missing install kits, accessory mismatch.
- **Rare but high-risk exceptions:** Product loaded to wrong route; critical shortage discovered after departure.
- **Separate sub-journeys created by this stage:** Replan/reload workflow due to shortage or route infeasibility.

#### Communication / Documentation / Escalation
- **Who must be informed:** Warehouse/load team, crew, and customer if timing shifts materially.
- **What must be documented:** Load verification, shortages, resequencing decisions.
- **What system record must be updated:** Route assignment, manifest/load record.
- **Escalation trigger:** Conflicts or shortages exceed dispatch authority.
- **Proof / evidence required:** Verified load record and route notes.

#### Metrics
- **Primary KPIs:** Load accuracy; route feasibility; on-time route start.
- **Failure indicators:** Same-day shortages, repeated resequencing, high late-arrival variance.

#### Hidden Knowledge
- **What outsiders usually miss:** A route can be operationally wrong even if the optimization software says it fits.
- **What hidden judgment matters most:** Balancing promised windows against crew reality and actual stop complexity.
- **What a novice gets wrong here:** Treating all jobs as equal-duration boxes.

#### Evidence / Open Questions
- **Direct expert quote or example:** “The objective is to build a feasible route and make sure the correct product, parts, and tools are loaded.”
- **Open question / ambiguity to validate:** What are the three most common stage-3 failures Javier would name first?

---

### Stage 4: Arrival & Home Access Confirmation
- **Objective:** Confirm the site matches pre-delivery assumptions and that safe access exists.
- **Start Trigger:** Crew arrives at the home.
- **Completion Condition:** Crew makes a go/no-go decision for entry and install.
- **Required Inputs:** Order packet, site notes, customer presence, actual home conditions.
- **Primary Owner / Decision Authority:** Crew lead, with dispatch or operations escalation if site conditions conflict with the order.
- **Other Roles Involved:** Dispatch, operations management, customer.
- **Systems / Tools Used:** Order packet, site notes, customer contact method, field documentation.
- **Happy Path Summary:** The crew finds the site as described, confirms access, and proceeds into removal/install without delay.

#### Customer Experience
- What the customer sees: Crew arrival, condition check, access verification.
- What the customer is likely feeling / worrying about: Whether the crew will say the site is installable and whether walls/floors will be protected.
- What the customer must do: Provide entry, identify destination room, and resolve any access blockers under their control.
- What the customer is told: Whether the job can proceed as planned or what mismatch must be addressed.

#### Pain Points / Failure Modes
1. **Pain Point:** Actual access path does not match readiness information. *(Draft.)*
   - Key variable that changes the correct response: Whether the mismatch is still safe with different equipment or a revised plan.
   - Correct response depends on: Safety, labor availability, and time impact.
   - Cascade risk if mishandled: Injury, property damage, failed stop, route disruption.
2. **Pain Point:** Customer is not ready or not fully present on arrival. *(Draft.)*
   - Key variable that changes the correct response: Whether the issue is solvable within route tolerance.
   - Correct response depends on: Reachability, prep gap, downstream stop pressure.
   - Cascade risk if mishandled: Long dwell time, missed windows, failed delivery.
3. **Pain Point:** Site conditions conflict with service sold. *(Draft.)*
   - Key variable that changes the correct response: Whether the conflict is a minor field workaround or a true no-go.
   - Correct response depends on: Scope, safety, and authority boundary.
   - Cascade risk if mishandled: Unauthorized work, damage, incomplete install, complaint escalation.

#### Exceptions
- **Common exceptions:** Gate/access problems, customer not fully ready, last-minute site mismatch.
- **Rare but high-risk exceptions:** Unsafe entry conditions or structural/safety hazards.
- **Separate sub-journeys created by this stage:** Field no-go and reschedule/escalation flow.

#### Communication / Documentation / Escalation
- **Who must be informed:** Customer immediately; dispatch/ops if site conflicts with the plan.
- **What must be documented:** Actual conditions, mismatch notes, photos.
- **What system record must be updated:** Field note / stop status.
- **Escalation trigger:** Site conditions do not match the order and crew cannot safely proceed.
- **Proof / evidence required:** Photos and crew notes.

#### Metrics
- **Primary KPIs:** First-attempt access success; arrival-to-go/no-go decision time.
- **Failure indicators:** High no-go rate; avoidable dwell time.

#### Hidden Knowledge
- **What outsiders usually miss:** The crew is making a real operational risk decision, not just “checking in.”
- **What hidden judgment matters most:** Deciding whether a mismatch is manageable or route-breaking.
- **What a novice gets wrong here:** Proceeding because the customer expects it, even when site conditions say otherwise.

#### Evidence / Open Questions
- **Direct expert quote or example:** “The crew lead escalates to dispatch or operations if site conditions do not match.”
- **Open question / ambiguity to validate:** Which field mismatches are most common versus most dangerous?

---

### Stage 5: Appliance Removal
- **Objective:** Remove the old unit safely when haul-away is included.
- **Start Trigger:** Access is confirmed.
- **Completion Condition:** Old unit is removed or an exception is documented.
- **Required Inputs:** Haul-away request, shutoff access, safety conditions, equipment, disposal rules.
- **Primary Owner / Decision Authority:** Crew lead, with management escalation for damage, safety, or scope disputes.
- **Other Roles Involved:** Customer, dispatch, operations management.
- **Systems / Tools Used:** Haul-away request, safety checklist, disposal rules.
- **Happy Path Summary:** The old unit is disconnected, moved safely, protected against damage, and loaded for disposal/haul-away.

#### Customer Experience
- What the customer sees: Old unit removal and protection of home surfaces.
- What the customer is likely feeling / worrying about: Damage risk, whether haul-away was actually included, and whether utilities are left in a usable state.
- What the customer must do: Provide access to the old unit and any required shutoffs.
- What the customer is told: Whether haul-away is included and whether any condition blocks safe removal.

#### Pain Points / Failure Modes
1. **Pain Point:** Shutoff access or disconnection conditions are not as expected. *(Draft.)*
   - Key variable that changes the correct response: Whether safe disconnection is possible within crew authority.
   - Correct response depends on: Utility condition, safety, and scope.
   - Cascade risk if mishandled: Damage, leak, unsafe condition, failed install.
2. **Pain Point:** Haul-away scope is disputed at the door. *(Draft.)*
   - Key variable that changes the correct response: Whether the service was sold/documented clearly.
   - Correct response depends on: Order record and authority to amend scope.
   - Cascade risk if mishandled: Customer dispute, extended dwell time, complaint.
3. **Pain Point:** Removal path creates damage or injury risk. *(Draft.)*
   - Key variable that changes the correct response: Whether alternate equipment/labor makes the move safe.
   - Correct response depends on: Site geometry and safe handling feasibility.
   - Cascade risk if mishandled: Property damage, injury, route disruption.

#### Exceptions
- **Common exceptions:** Old unit not disconnected; haul-away misunderstanding.
- **Rare but high-risk exceptions:** Unsafe utility condition uncovered during removal.
- **Separate sub-journeys created by this stage:** Damage claim or utility/safety escalation.

#### Communication / Documentation / Escalation
- **Who must be informed:** Customer; management if damage, safety, or scope dispute appears.
- **What must be documented:** Condition of old unit area, scope dispute, damage notes.
- **What system record must be updated:** Stop notes and reason codes.
- **Escalation trigger:** Damage, safety, or scope dispute exceeds crew authority.
- **Proof / evidence required:** Photos and exception notes.

#### Metrics
- **Primary KPIs:** Haul-away completion rate; removal damage incident rate.
- **Failure indicators:** Repeated scope disputes; removal-related delays.

#### Hidden Knowledge
- **What outsiders usually miss:** Removal is often where hidden site/scope issues surface.
- **What hidden judgment matters most:** Knowing when “can probably do it” is not safe enough.
- **What a novice gets wrong here:** Treating removal as routine labor instead of a risk gate.

#### Evidence / Open Questions
- **Direct expert quote or example:** “Decision authority: crew lead, with management escalation for damage, safety, or scope disputes.”
- **Open question / ambiguity to validate:** Which removal failures are most common in washer/dryer jobs specifically?

---

### Stage 6: Install & Utility Connection
- **Objective:** Place and connect the new unit correctly and to code.
- **Start Trigger:** After removal or once the install area is clear.
- **Completion Condition:** Appliance is connected, leveled, and ready for testing.
- **Required Inputs:** Product specs, install kit, utilities condition, tools, code requirements.
- **Primary Owner / Decision Authority:** Installer or crew lead, with technical or management escalation if code, safety, or product issues appear.
- **Other Roles Involved:** Customer, dispatch, technical support, operations management.
- **Systems / Tools Used:** Product specs, install kit, tools, code guidance.
- **Happy Path Summary:** The crew places the unit, connects utilities, levels it, and reaches a test-ready state without code or safety issues.

#### Customer Experience
- What the customer sees: Placement, hookup, leveling, and crew workmanship.
- What the customer is likely feeling / worrying about: Whether the install is correct, safe, and clean.
- What the customer must do: Provide access and sometimes approve placement decisions.
- What the customer is told: What is being connected, any constraint, and whether anything cannot be completed to code.

#### Pain Points / Failure Modes
1. **Pain Point:** Code or safety issue appears during hookup. *(Directly implied by escalation rule.)*
   - Key variable that changes the correct response: Whether the issue is remediable within field authority.
   - Correct response depends on: Code requirements, safety risk, and technical support guidance.
   - Cascade risk if mishandled: Unsafe install, liability, callback, customer harm.
2. **Pain Point:** Product issue or missing install kit blocks connection. *(Draft.)*
   - Key variable that changes the correct response: Whether a field workaround is allowed or a revisit is required.
   - Correct response depends on: Parts availability and install standard.
   - Cascade risk if mishandled: Incomplete job, repeat trip, customer frustration.
3. **Pain Point:** Utilities condition differs from what readiness review suggested. *(Draft.)*
   - Key variable that changes the correct response: Whether the variance is safe and within scope.
   - Correct response depends on: Utility state, scope, and code boundary.
   - Cascade risk if mishandled: Failed install, damage, dispute, complaint.

#### Exceptions
- **Common exceptions:** Missing kit/parts, outlet/hookup mismatch, placement constraint.
- **Rare but high-risk exceptions:** Code violation, safety hazard, defective product.
- **Separate sub-journeys created by this stage:** Technical support escalation or revisit workflow.

#### Communication / Documentation / Escalation
- **Who must be informed:** Customer about install limitations; technical support/management for code, safety, or product issues.
- **What must be documented:** Install limitation, parts gap, code issue, reason codes.
- **What system record must be updated:** Field install note and stop disposition.
- **Escalation trigger:** Code, safety, or product issues appear.
- **Proof / evidence required:** Photos, checklist, specific defect or code notes.

#### Metrics
- **Primary KPIs:** Install completion rate; callback rate; average install time.
- **Failure indicators:** Repeat visits, safety escalations, post-install complaints.

#### Hidden Knowledge
- **What outsiders usually miss:** “Connected” is not the same as “correct, safe, and to code.”
- **What hidden judgment matters most:** Where the field authority line stops.
- **What a novice gets wrong here:** Forcing completion instead of escalating when the install is no longer standard.

#### Evidence / Open Questions
- **Direct expert quote or example:** “The installer or crew lead escalates to technical support or management when code, safety, or product issues appear.”
- **Open question / ambiguity to validate:** Which install problems should always force a no-go versus a workaround?

---

### Stage 7: Testing & Customer Sign-Off
- **Objective:** Verify the unit works and secure customer acceptance.
- **Start Trigger:** Installation is complete.
- **Completion Condition:** Tests pass, customer is briefed, and sign-off is captured or an exception is documented.
- **Required Inputs:** Completed install, test checklist, customer present, photos or notes.
- **Primary Owner / Decision Authority:** Crew lead, with dispatch or operations escalation for disputes, damage, or failures.
- **Other Roles Involved:** Customer, dispatch, operations management.
- **Systems / Tools Used:** Test checklist, photo capture, POD/signature tool.
- **Happy Path Summary:** The crew runs functional checks, explains the result to the customer, captures proof, and closes the stop cleanly.

#### Customer Experience
- What the customer sees: Live testing, explanation, sign-off request.
- What the customer is likely feeling / worrying about: Whether the unit actually works and whether any issue will be ignored once the crew leaves.
- What the customer must do: Observe, ask questions, and sign if satisfied.
- What the customer is told: What was tested, what to watch for, and what happens if something is wrong.

#### Pain Points / Failure Modes
1. **Pain Point:** Unit fails test after install. *(Draft.)*
   - Key variable that changes the correct response: Whether the failure is fixable immediately or requires handoff.
   - Correct response depends on: Severity, parts/tools, and route time.
   - Cascade risk if mishandled: Repeat visit, complaint, low trust, unresolved safety/performance issue.
2. **Pain Point:** Customer disputes quality, damage, or completeness. *(Draft.)*
   - Key variable that changes the correct response: Whether evidence and scope are clear.
   - Correct response depends on: Photos, notes, explanation quality, and authority to resolve.
   - Cascade risk if mishandled: Escalation, claim, chargeback, poor CSAT.
3. **Pain Point:** Sign-off or POD is not captured correctly. *(Draft.)*
   - Key variable that changes the correct response: Whether proof can still be captured before departure.
   - Correct response depends on: Device/process reliability and customer availability.
   - Cascade risk if mishandled: Billing/proof problems, dispute vulnerability, weak handoff to support.

#### Exceptions
- **Common exceptions:** Customer questions after test; incomplete documentation.
- **Rare but high-risk exceptions:** Hidden defect or damage discovered at sign-off.
- **Separate sub-journeys created by this stage:** Post-install complaint/escalation case.

#### Communication / Documentation / Escalation
- **Who must be informed:** Customer first; dispatch/ops if failures, disputes, or damage appear.
- **What must be documented:** Test result, sign-off status, photos, dispute notes.
- **What system record must be updated:** POD, completion status, reason codes.
- **Escalation trigger:** Dispute, damage, or failure cannot be resolved in the stop.
- **Proof / evidence required:** Photos, checklist result, signature or documented refusal.

#### Metrics
- **Primary KPIs:** Test pass rate; sign-off capture rate; photo compliance.
- **Failure indicators:** High post-install callback rate; undocumented completions.

#### Hidden Knowledge
- **What outsiders usually miss:** Sign-off is a risk-control step, not just paperwork.
- **What hidden judgment matters most:** Whether a “small issue” can be closed now or will become a bigger complaint later.
- **What a novice gets wrong here:** Rushing the close because the route is behind.

#### Evidence / Open Questions
- **Direct expert quote or example:** “Decision authority: crew lead, with dispatch or operations escalation for disputes, damage, or failures.”
- **Open question / ambiguity to validate:** What exact test sequence and customer briefing language does Javier consider non-negotiable?

---

### Stage 8: Post-Install Issue Resolution
- **Objective:** Resolve defects, damage, incomplete work, or customer complaints quickly.
- **Start Trigger:** An issue is reported or documented after the visit.
- **Completion Condition:** Remedy is completed or ownership and timeline are handed off.
- **Required Inputs:** Install notes, photos, reason codes, complaint details, service history.
- **Primary Owner / Decision Authority:** Customer care, field service, or operations management depending on severity and cost.
- **Other Roles Involved:** Customer, dispatch, crew/installer, management.
- **Systems / Tools Used:** Case notes, complaint details, service history, reason codes.
- **Happy Path Summary:** The issue is classified correctly, routed to the right owner, supported by good evidence, and either resolved or cleanly handed off with a timeline.

#### Customer Experience
- What the customer sees: Follow-up communication, issue ownership, and remedy timeline.
- What the customer is likely feeling / worrying about: Whether anyone owns the issue and how long the fix will take.
- What the customer must do: Report the issue and provide any needed details or availability.
- What the customer is told: Who owns the case, what happens next, and expected timing.

#### Pain Points / Failure Modes
1. **Pain Point:** Severity is classified incorrectly. *(Directly implied by authority shifting by severity/cost.)*
   - Key variable that changes the correct response: Severity and cost.
   - Correct response depends on: Accurate evidence, issue type, and ownership rules.
   - Cascade risk if mishandled: Delayed remedy, extra touches, angry customer, avoidable cost.
2. **Pain Point:** Evidence from the original stop is incomplete. *(Draft.)*
   - Key variable that changes the correct response: Whether the original crew notes/photos are sufficient to decide next action.
   - Correct response depends on: Documentation quality and claim type.
   - Cascade risk if mishandled: Rework, dispute, weak accountability, longer resolution time.
3. **Pain Point:** Ownership between customer care, field service, and ops is unclear. *(Draft.)*
   - Key variable that changes the correct response: Whether the issue is customer communication, field remedy, or management exception.
   - Correct response depends on: Clear routing rules and severity threshold.
   - Cascade risk if mishandled: Dropped cases, duplicated work, poor recovery experience.

#### Exceptions
- **Common exceptions:** Minor complaints, incomplete work, evidence review.
- **Rare but high-risk exceptions:** Safety claim, major damage claim, severe product defect.
- **Separate sub-journeys created by this stage:** Revisit/rework case or claim-resolution workflow.

#### Communication / Documentation / Escalation
- **Who must be informed:** Customer, assigned owner, and management for high-severity/cost cases.
- **What must be documented:** Complaint details, service history, evidence, owner, promised timeline.
- **What system record must be updated:** Case file / service record.
- **Escalation trigger:** Severity or cost exceeds front-line authority.
- **Proof / evidence required:** Install notes, photos, reason codes, history.

#### Metrics
- **Primary KPIs:** Resolution time; repeat visit rate; complaint recovery quality.
- **Failure indicators:** Long open cases; repeated ownership transfers; unresolved complaints.

#### Hidden Knowledge
- **What outsiders usually miss:** Fast ownership is often more important to the customer than instant resolution.
- **What hidden judgment matters most:** Matching issue severity to the right owner on the first handoff.
- **What a novice gets wrong here:** Treating all complaints as the same workflow.

#### Evidence / Open Questions
- **Direct expert quote or example:** “Decision authority shifts between customer care, field service, and operations management based on severity and cost.”
- **Open question / ambiguity to validate:** What are the exact routing thresholds by severity, cost, and issue type?

---

### 4) Cross-Stage Synthesis

### Handoffs That Matter Most
- **Stage 1 -> Stage 2:** If order data is wrong, readiness review starts from a false premise.
- **Stage 2 -> Stage 3:** Route quality depends on whether readiness truth made it into dispatch planning.
- **Stage 4 -> Stage 5/6:** The field crew's go/no-go decision determines whether removal/install can proceed safely.
- **Stage 7 -> Stage 8:** Resolution quality depends on test evidence, photos, and sign-off notes captured before departure.

### Top Cross-Stage Failure Patterns
- Upstream data quality problems create downstream field failures.
- Access/readiness truth is discovered too late, after route capacity has already been committed.
- Authority boundaries matter: the wrong person holding a decision too long creates safety, cost, and customer trust damage.

### Critical Decision Variables Across The Journey
- **Can this be corrected remotely before dispatch?** -> changes decisions in stages 1-3.
- **Can the crew still complete safely within scope?** -> changes decisions in stages 4-6.
- **How severe and costly is the issue?** -> changes decisions in stages 7-8.

### Most Important Escalation Types
- Safety/code escalation
- Site/access mismatch escalation
- Product/parts shortage escalation
- Damage/complaint recovery escalation

### Terms / Jargon To Define
- **Haul-away:** Removal of the old appliance as part of the service package.
- **Stacked unit:** Washer/dryer configuration whose install/removal constraints may differ materially from a side-by-side setup.
- **Hoist job:** Delivery requiring non-standard lifting/access handling.
- **Route feasibility:** Whether the route can still be completed realistically with the crew, stop times, and constraints actually present.

### Follow-Up Questions For Next Interview
- What are the top three real failure modes in stage 1?
- For stages 3-8, what are Javier's actual examples, not just our first-pass hypotheses?
- What exact systems, note language, and reason codes are used at each escalation point?
- Which stage has the most hidden judgment after stage 2?

---

### 5) Quality Check Before Finalizing

**Current status:** Draft is useful, but not yet final.

- [x] every stage has a clear objective, trigger, and completion condition
- [~] customer and internal moments are both represented
- [~] decision authority is explicit where ambiguity matters
- [x] unclear points are captured as open questions
- [ ] each important stage has 3 fully expert-validated failure modes
- [ ] each failure mode includes expert-confirmed variable and downstream risk
- [ ] exceptions and escalations are fully validated beyond stage 2
- [ ] metrics are tied to confirmed operational instrumentation rather than draft proxy KPIs

**Recommended next step:** Run a follow-up interview pass focused only on pain points, decision variables, and escalation thresholds for stages 1 and 3-8, then upgrade this file from `v1-draft` to `v1`.