# Journey Map: Customer Booking Journey

This document describes the journey map "Customer Booking Journey" exported from Emgram. It is a source-of-truth reference for understanding the stages a primary actor moves through and the perspectives (lenses) considered at each stage.

## Overview
- Title: Customer Booking Journey
- Status: active
- Intent: not set
- Map level: not set
- Number of stages: 7
- Number of lenses: 8
- Total cells: 56 (filled: 56, confirmed: 0, locked: 0)

## Journey Context
- Primary actor: Customer (English or Spanish-speaking) browsing and booking chair/table rentals online
- Journey scope: Covers the full customer-facing booking experience from first landing on the webapp through order confirmation and self-service order lookup. Excludes internal staff operations, delivery logistics, and route planning (handled in Maps 2–4). Excludes B2B/contract accounts.
- Start point: Customer lands on the Blooming Party Rentals webapp for the first time or returns to book a rental
- End point: Customer has received order confirmation (email + SMS), their order is recorded in the system, payment is captured or deposit collected, and they can look up their order status at any time
- Duration: 5–15 minutes for first-time customers; 3–5 minutes for returning customers who know what they want
- Success metrics: Checkout conversion rate > 70%; payment success rate > 95%; order confirmation delivery (email + SMS) < 60 seconds; zero double-bookings; zero out-of-stock orders confirmed; customer lookup self-service resolves without staff contact
- Key stakeholders: Customer (primary actor); Blooming Party Rentals business owner (admin config); Operations staff (receive new order alerts); Stripe (payment processing); Supabase (inventory + order data); SendGrid (email confirmations); Twilio (SMS confirmations)
- Dependencies and assumptions: Supabase real-time inventory availability API; Stripe payment API + webhooks; SendGrid transactional email API; Twilio SMS API; Google Maps address validation for delivery zone check; Admin-configured settings (prices, deposit %, tax rate, delivery zones, cancellation window, pickup hours)
- Pain points summary: Customers may not know the service area before entering address, causing late-stage rejection. Language barrier for Spanish-speaking customers if EN/ES toggle is not prominent. Date availability confusion if real-time stock updates are slow. Payment friction if deposit vs. full-pay logic is unclear. Customers calling staff for order status instead of using self-service lookup.
- Opportunities: Auto-detect browser language to reduce friction at entry. Show delivery zone map upfront so customers self-qualify. Real-time quantity cap on product selector tied to live inventory. Bilingual confirmation messages reduce inbound calls. Self-service order lookup + cancellation reduces staff workload by estimated 40%.
- Version: v1.0

## AI Behaviour Settings
- Interview depth: not set
- Insight standard: not set
- Lens priority: not set
- Emotional mapping enabled: unknown
- Business impact framing enabled: unknown
- Auto-confirm writes enabled: unknown

## Stages
Stages represent the sequential phases of the journey. Each stage has a goal and a primary actor lens.

### Stage 1: Land & Language Select
Goal: Customer lands on the webapp, browser language is detected, and preferred language (EN/ES) is set and persisted for the entire session
Primary actor lens: lens-2

### Stage 2: Browse Products
Goal: Customer has viewed all available rental items with real-time pricing and stock availability for their intended dates
Primary actor lens: lens-2

### Stage 3: Select Date & Fulfillment
Goal: Customer has selected rental start and return dates, chosen delivery or pickup, and availability has been confirmed in real time with no overbooking risk
Primary actor lens: lens-2

### Stage 4: Order Summary & Checkout
Goal: Customer has reviewed itemized order with correct pricing, tax, and fees, and has entered valid contact information
Primary actor lens: lens-2

### Stage 5: Payment Processing
Goal: Payment is captured or deposit collected via Stripe (or Pay in Person bypass for pickup), order record created in DB, and inventory allocated for selected dates
Primary actor lens: lens-5

### Stage 6: Order Confirmation
Goal: Customer receives confirmation number on screen and confirmation email + SMS in their chosen language within 60 seconds of booking
Primary actor lens: lens-5

### Stage 7: Order Lookup & Self-Service
Goal: Customer can retrieve their order status at any time using email + order number, and can self-cancel if within the configured cancellation window
Primary actor lens: lens-2

## Lenses (Actors)
Lenses represent the perspectives or actors considered at each stage.

### Description

### Customer
Actor type: customer
Persona: English or Spanish-speaking customer in North Austin or Round Rock, TX planning a party or event. May be a first-time renter or a returning customer. Primarily on mobile. May not be tech-savvy — expects a simple, friendly, local-business experience.
Primary goal: Find the right chairs/tables, pick dates, choose delivery or pickup, pay, and get a confirmation — all without calling the business
Constraints: Must be within the Blooming Party Rentals service area (North Austin / Round Rock) for delivery orders. Cannot book items unavailable on selected dates. Must provide valid contact info (name, phone, email). Cancellation only allowed within configured window (admin-set, e.g. 48 hrs before rental start).

### Internal (Staff)
Actor type: internal
Persona: Blooming Party Rentals staff member or business owner monitoring incoming orders. Receives new order alerts via email. May need to handle edge cases (address borderline, payment issue, special requests) but ideally the self-service flow handles everything automatically.
Primary goal: Ensure every booking is valid, paid, and actionable with zero manual intervention required for standard orders
Constraints: Staff should not need to touch standard orders — the portal handles them end-to-end. Only intervenes for exceptions. Admin configures all pricing, zones, and policies via settings panel — not via code changes.

### Handoff
Actor type: handoff
Persona: The system handoff layer — captures what event triggers each stage, what data must exist before it begins, what is produced at the end, and how control flows to the next stage or external system (Stripe, Supabase, SendGrid, Twilio).
Primary goal: Ensure every stage has a defined trigger event, required prerequisite data, and a clear output that feeds the next stage — making the full booking flow executable and verifiable end-to-end
Constraints: Every handoff cell must define trigger_event, prerequisite_data, and output. Failure recovery must be documented for any stage that calls an external API. No stage may begin without its prerequisites confirmed.

### Engineering
Actor type: engineering
Persona: The technical implementation layer — documents which Next.js API routes, Supabase queries, Stripe calls, Google Maps validations, SendGrid templates, and Twilio triggers fire at each stage, along with data shapes, error states, and performance expectations.
Primary goal: Provide a complete, stage-by-stage technical specification so the developer can implement each module knowing exactly which tools to call, with which inputs, and how to handle failures
Constraints: Must reference exact API names and endpoint patterns. Must document all required input fields and expected response shapes. Error states and edge cases must be listed for every external call. Must flag environment variables required per stage. Mobile-first responsive design is a non-negotiable constraint for all frontend stages.

### Metrics
Actor type: metrics
Persona: The quality and performance measurement layer — tracks success rates, conversion, error rates, timing, and customer satisfaction signals at each stage of the booking flow to surface where the portal is working and where it is leaking customers or causing failures.
Primary goal: Ensure every stage has measurable exit criteria and surface gaps or failure modes before they affect the customer experience or business revenue
Constraints: Metrics must be specific and measurable — no aspirational targets. Must distinguish between customer-facing metrics (conversion, CSAT) and system metrics (error rate, API latency). Must flag SLA compliance per stage. Metrics are re-evaluated after any system change.

### Product Manager
Actor type: internal
Persona: Product Manager responsible for the Blooming Party Rentals webapp — owns the booking experience, conversion funnel, and customer self-service features. Balances business goals (revenue, conversion) with customer experience and technical feasibility.
Primary goal: Maximize booking conversion rate while minimizing friction and support burden. Ensure the webapp is intuitive, fast, and accessible to both English and Spanish-speaking customers.
Constraints: Must work within existing tech stack (Supabase, Stripe, SendGrid, Twilio). Limited engineering bandwidth — prioritize high-impact, low-complexity improvements. All changes must maintain bilingual parity (EN/ES).
Role prompt: You are capturing the internal employee perspective at each stage of this journey. For each stage focus on: Task / Objective (what they are responsible for at this step), Entry Point / Trigger (what initiates their involvement), Tools & Systems Used (what platforms or devices they rely on), Information Needs (what data or context they need), Decisions Required (judgment calls they must make), Friction Points (what slows them down or causes errors), Assumptions Being Made (what they believe that may cause issues if wrong), Handoff Dependencies (what they need from a previous step or person), Success Criteria (what completing this step correctly looks like), Output / Deliverable (what they produce or pass forward), Employee Constraints (limitations affecting how they perform), and Pain Points (recurring frustrations or gaps). Be specific. Use operational language. Focus on process gaps and friction.

### XU Designer
Actor type: internal
Role prompt: You are capturing the internal employee perspective at each stage of this journey. For each stage focus on: Task / Objective (what they are responsible for at this step), Entry Point / Trigger (what initiates their involvement), Tools & Systems Used (what platforms or devices they rely on), Information Needs (what data or context they need), Decisions Required (judgment calls they must make), Friction Points (what slows them down or causes errors), Assumptions Being Made (what they believe that may cause issues if wrong), Handoff Dependencies (what they need from a previous step or person), Success Criteria (what completing this step correctly looks like), Output / Deliverable (what they produce or pass forward), Employee Constraints (limitations affecting how they perform), and Pain Points (recurring frustrations or gaps). Be specific. Use operational language. Focus on process gaps and friction.

## Coverage Matrix
Each cell shows the state of the intersection between a lens (row) and a stage (column). States: confirmed, draft, empty, locked.

| Lens \ Stage | Land & Language Select | Browse Products | Select Date & Fulfillment | Order Summary & Checkout | Payment Processing | Order Confirmation | Order Lookup & Self-Service |
|---|---|---|---|---|---|---|---|
| Description | draft | draft | draft | draft | draft | draft | draft |
| Customer | draft | draft | draft | draft | draft | draft | draft |
| Internal (Staff) | draft | draft | draft | draft | draft | draft | draft |
| Handoff | draft | draft | draft | draft | draft | draft | draft |
| Engineering | draft | draft | draft | draft | draft | draft | draft |
| Metrics | draft | draft | draft | draft | draft | draft | draft |
| Product Manager | draft | draft | draft | draft | draft | draft | draft |
| XU Designer | draft | draft | draft | draft | draft | draft | draft |

## Cell Details
Each section below describes one cell at the intersection of a lens and a stage. Cells are listed stage-by-stage in journey order.

### Cell: Description during Land & Language Select
This cell describes the perspective of "Description" during the "Land & Language Select" stage.
State: draft. Locked: no.

Customer arrives at the webapp via link, search, or direct URL. Browser language is auto-detected and the UI defaults to English or Spanish. A persistent EN | ES toggle is visible in the top nav bar on every page. All UI strings, labels, errors, and confirmation text render in the chosen language. Language preference is saved to localStorage for return visits. No login or account required.

### Cell: Customer during Land & Language Select
This cell describes the perspective of "Customer" during the "Land & Language Select" stage.
State: draft. Locked: no.

Customer visits the webapp for the first time or follows a link. They immediately see the language toggle in the nav bar. If their browser is set to Spanish, the page loads fully in Spanish. They can switch language at any time with one tap or click. No account, no login, no friction — they land directly into the rental experience.

Actor fields:
- emotions: Curious and cautious — first impression of the business
- assumptions: Assumes the site works in their language; may leave if it doesn't
- entry_trigger: Customer navigates to webapp URL
- expected_output: UI fully rendered in chosen language with EN|ES toggle visible
- friction_points: Browser language not detected; toggle not prominent enough
- information_needs: Language options and ability to switch at any time
- channel_touchpoint: Web browser (desktop or mobile)
- decisions_required: Language preference (EN or ES)
- acceptance_criteria: UI renders in correct language; toggle works; preference persists across pages

### Cell: Internal (Staff) during Land & Language Select
This cell describes the perspective of "Internal (Staff)" during the "Land & Language Select" stage.
State: draft. Locked: no.

N/A — Staff does not act at this stage. Language selection is fully automated via browser detection and localStorage. Staff may configure the fallback default language (EN or ES) via the admin settings panel but has no role during the customer session.

Actor fields:
- emotions: Passive — no action required
- assumptions: Admin has configured the default language fallback prior to customer sessions
- pain_points: Outdated or missing language setting causes customers to see wrong locale on first load
- entry_trigger: Customer navigates to webapp — language detection runs automatically
- tools_systems: Admin settings panel (language default config)
- task_objective: Maintain accurate admin settings (default language, EN/ES fallback) so the customer session starts in the correct language without staff intervention
- expected_output: Customer arrives with correct language set
- friction_points: Admin forgets to set language default; toggle not tested in both locales before go-live
- success_criteria: Customer session starts in correct language with no staff involvement
- information_needs: How to set the default language fallback in the admin settings panel
- channel_touchpoint: Admin settings panel (not during customer session)
- decisions_required: None during customer session — language default configured once in admin panel before launch
- output_deliverable: N/A — staff output is pre-session config, not a runtime deliverable
- acceptance_criteria: N/A — staff does not act at this stage
- employee_constraints: Staff must not change language settings during active customer sessions
- handoff_dependencies: Language default setting persisted in settings table before customer session begins

### Cell: Handoff during Land & Language Select
This cell describes the perspective of "Handoff" during the "Land & Language Select" stage.
State: draft. Locked: no.

Trigger: Customer navigates to webapp URL (direct, referral, or search). Prerequisite: None — this is the entry point of the journey. Output: Language preference set in localStorage; i18n context loaded; all UI strings rendered in chosen language (EN or ES). Flows to: Browse Products (s2). Failure recovery: If browser language is undetectable, default to English; EN|ES toggle is always visible and functional.

Actor fields:
- trigger_event: Customer navigates to webapp URL (direct, referral, or search result)
- handoff_output: Language preference set in localStorage; i18n context loaded; all UI strings rendered in chosen language
- handoff_timing: Immediate on page load
- upstream_actor: External (customer arrives from outside the system)
- downstream_actor: Browse Products stage (s2)
- failure_recovery: Browser language undetectable → default to English; EN|ES toggle always visible and functional
- validation_rules: Language code must be 'en' or 'es'; fallback to 'en' for any other value
- prerequisite_data: None — entry point of journey
- communication_method: Client-side localStorage + next-i18next context
- data_retention_policy: Language preference stored in localStorage; persists across sessions until user changes it
- upstream_dependencies: Next.js app deployed and accessible; i18n translation files loaded
- prerequisite_data_detail: No prerequisites — this is the journey entry point

### Cell: Engineering during Land & Language Select
This cell describes the perspective of "Engineering" during the "Land & Language Select" stage.
State: draft. Locked: no.

Frontend: Web application page wrapped in internationalization provider. Locale detection: browser language detection → set locale to 'es' if Spanish detected; else 'en'. Persist to browser local storage key: 'preferred_language'. EN|ES toggle calls i18n language change function client-side with no page reload. Translation files: /public/locales/en/common.json and /public/locales/es/common.json covering all UI strings. No API calls at this stage. ENV required: none yet. Performance: First Contentful Paint < 2s; language switch < 100ms (client-side only).

Notes: Translation JSON files must be fully populated for both locales before deploy. Missing translation keys cause untranslated strings to appear as key names. All new UI strings must be added to both en.json and es.json before deploy. Supported locales: ['en', 'es'] only. Any other browser language → default 'en'. navigator.language undefined → default to 'en'; localStorage unavailable (private browsing) → fall back to in-memory language state. FCP < 2s on mobile 4G; language switch < 100ms client-side. Log language split (EN vs ES) in analytics.

Actor fields:
- assumptions: Translation JSON files fully populated for both locales before deploy
- data_inputs: navigator.language string; localStorage 'preferred_language' value
- entry_point: Customer navigates to webapp URL
- data_outputs: Active locale ('en' or 'es'); i18n context loaded across all components
- task_objective: Detect browser language, set locale, render all UI strings in correct language
- friction_points: Missing translation keys cause untranslated strings to appear as key names
- success_criteria: Page renders in correct language on first load; toggle switches language without page reload
- information_needs: Complete en.json and es.json in /public/locales/
- tools_and_systems: Next.js _app.tsx with next-i18next I18nextProvider; localStorage API; navigator.language browser API
- decisions_required: None — automated
- output_deliverable: Localized page render; language preference persisted
- audit_logging_needs: Log language split (EN vs ES) in analytics
- business_rules_logic: Supported locales: ['en', 'es'] only. Any other browser language → default 'en'
- employee_constraints: All new UI strings must be added to both en.json and es.json before deploy
- handoff_dependencies: None — entry point
- security_permissions: No auth required — public page
- system_service_owner: Web application frontend
- error_states_edge_cases: navigator.language undefined → default to 'en'; localStorage unavailable (private browsing) → fall back to in-memory language state
- performance_requirements: FCP < 2s on mobile 4G; language switch < 100ms client-side
- data_storage_requirements: localStorage key: 'preferred_language' value: 'en' | 'es'
- api_integration_dependencies: None — no API calls at this stage

### Cell: Metrics during Land & Language Select
This cell describes the perspective of "Metrics" during the "Land & Language Select" stage.
State: draft. Locked: no.

Completion rate: % of visitors who proceed to product browse — target > 95% (near-zero entry barrier). Drop-off rate: % who leave without viewing products — target < 5%. Language split: % of sessions in EN vs ES — track to inform content and marketing priority. Page load time: target FCP < 2s on mobile 4G. Language switch latency: < 100ms. SLA: No API dependencies at this stage — 100% availability expected. Volume: track daily unique session starts.

Actor fields:
- csat_score: 9
- error_rate: 1
- stage_health: 9
- drop_off_rate: 5
- completion_rate: 95
- volume_frequency: Every session start — tracked daily
- sla_compliance_rate: 100
- avg_time_to_complete: 0.1

### Cell: Product Manager during Land & Language Select
This cell describes the perspective of "Product Manager" during the "Land & Language Select" stage.
State: draft. Locked: no.

User Story: As a Spanish-speaking customer, I want the webapp to auto-detect my browser language and show a clear EN|ES toggle, so I can browse and book in my preferred language without friction.

Acceptance Criteria:
- Browser language detected on first load
- UI renders in correct language (EN or ES) immediately
- EN|ES toggle visible in top nav on every page
- Language preference persists across pages and return visits
- Toggle switches language without page reload (< 100ms)

Value: Reduces bounce rate for Spanish-speaking customers; increases conversion by removing language barrier at entry point.

Actor fields:
- assumptions: Browser locale is a reliable signal for language preference; toggle placement impacts conversion
- pain_points: No current data on how many Spanish speakers are bouncing due to language barrier
- entry_trigger: Customer lands on webapp homepage
- tools_systems: Analytics (GA4 or similar) to track language selection rate and bounce rate by locale
- task_objective: Ensure language toggle is prominent and auto-detects browser locale to reduce friction for Spanish-speaking customers
- friction_points: If toggle is buried or not obvious, Spanish speakers may bounce immediately
- success_criteria: Language selection rate > 90% for non-English browsers; bounce rate parity between EN/ES sessions
- information_needs: What % of visitors are Spanish-speaking? Do they find the toggle? What's bounce rate by language?
- decisions_required: Should language auto-detect be default-on or opt-in? Should we A/B test toggle placement?
- output_deliverable: PRD for language toggle enhancement; A/B test plan for toggle placement
- employee_constraints: Limited eng bandwidth — must be low-complexity change
- handoff_dependencies: Engineering to implement auto-detect; Analytics to instrument language selection events

### Cell: XU Designer during Land & Language Select
This cell describes the perspective of "XU Designer" during the "Land & Language Select" stage.
State: draft. Locked: no.

UX Designer is responsible for the EN|ES language toggle component — its placement, visual prominence, and accessibility. The toggle must be visible above the fold on all mobile viewports without scrolling. Spanish text runs 20–30% longer than English; every UI component must be designed to absorb that expansion without truncation or layout breaks. FCP < 2s requires lazy-loading non-critical assets. Toggle active/inactive states must meet WCAG AA contrast. Tap target minimum 44×44px per Apple HIG.

Actor fields:
- assumptions: navigator.language is a reliable proxy for language preference; localStorage persists across typical mobile sessions
- pain_points: Developers sizing buttons for English-only causing ES overflow post-launch; toggle visually buried in nav causing Spanish-speaker bounce
- entry_trigger: Customer lands on webapp homepage for the first time or returns to book
- tools_systems: Figma (component design), Tailwind CSS utility classes, browser devtools (language simulation via Accept-Language override)
- task_objective: Design the EN|ES language toggle — placement, visual hierarchy, tap target size, and accessibility; establish bilingual layout guidelines so all components handle Spanish text expansion without breaking
- friction_points: Spanish text overflow in buttons or labels if designed only for English string lengths; toggle deprioritized as 'small' when it has outsized conversion impact for Spanish speakers
- success_criteria: Toggle visible on all viewports without scrolling; all strings render without truncation in both EN and ES; FCP < 2s on mobile 4G; toggle meets WCAG AA
- information_needs: Maximum Spanish string lengths for all nav and hero copy; mobile viewport breakpoints; WCAG AA contrast requirements for toggle states
- decisions_required: Toggle placement (top-nav vs. hero vs. floating pill); active state visual treatment (filled vs. outlined); mobile-first vs. desktop-first layout direction
- output_deliverable: Language toggle component spec in Figma; bilingual layout guidelines doc; mobile-first header redline
- employee_constraints: Every new UI component must be reviewed with Spanish copy loaded — no single-language sign-off accepted
- handoff_dependencies: Complete EN/ES translation strings must exist before final component sizing; analytics event schema agreed with Engineering before instrumentation

### Cell: Description during Browse Products
This cell describes the perspective of "Description" during the "Browse Products" stage.
State: draft. Locked: no.

Customer views the product catalog — standard folding chairs, 6ft rectangular tables, and 8ft rectangular tables. Each card shows an admin-uploadable photo, product name in EN/ES, price per unit per day, seating capacity, dimensions, and ideal use case. Quantity selector shows min 1 and max = real-time available stock for the customer's selected dates. Quantity cap updates dynamically when dates change.

### Cell: Customer during Browse Products
This cell describes the perspective of "Customer" during the "Browse Products" stage.
State: draft. Locked: no.

Customer browses 3 product types. Each card shows a photo, name in their language, price per day, and a +/- quantity selector. They feel confident — dimensions, seating capacity, and ideal use are clearly described. Maximum quantity reflects real-time availability for their chosen dates (or unrestricted if dates not yet selected). They can adjust quantities freely before committing.

Actor fields:
- emotions: Interested and evaluating — comparing products and prices
- assumptions: Assumes photos are accurate and prices are current
- entry_trigger: Customer arrives on product listing page
- expected_output: Customer has selected quantities for desired items
- friction_points: No photos loaded; unclear dimensions; quantity cap not explained
- information_needs: Price per day, dimensions, capacity, availability for dates
- channel_touchpoint: Product listing page (mobile-first)
- decisions_required: Which products to rent and how many
- acceptance_criteria: At least one item with qty > 0 selected; customer understands what they are renting

### Cell: Internal (Staff) during Browse Products
This cell describes the perspective of "Internal (Staff)" during the "Browse Products" stage.
State: draft. Locked: no.

N/A — Staff does not act during product browsing. Staff manages product content (photos, names in EN/ES, descriptions, and prices per day) via the admin settings panel outside of customer sessions. Product updates are reflected immediately in the storefront.

Actor fields:
- emotions: Passive — product content pre-configured
- assumptions: Product catalog is fully seeded and photos are uploaded before go-live
- pain_points: Outdated product photos or stale pricing causes customer confusion and potential order disputes
- entry_trigger: Customer views product listing — catalog is read from Supabase in real time
- tools_systems: Admin settings panel (product management), Supabase Storage (photo upload)
- task_objective: Maintain accurate product catalog (photos, names in EN/ES, descriptions, prices) in the admin panel so customers see correct and current rental information
- expected_output: Product content visible to customer is accurate and current
- friction_points: Staff updates price in admin but forgets to update the corresponding Spanish description
- success_criteria: All 3 product types visible with correct pricing and bilingual descriptions
- information_needs: How to update product photos, EN/ES names, descriptions, and price per day in the admin panel
- channel_touchpoint: Admin settings panel (pre-session configuration)
- decisions_required: None during customer session — products managed in admin panel outside session
- output_deliverable: N/A — staff output is pre-session catalog config
- acceptance_criteria: N/A — staff does not act at this stage
- employee_constraints: Price changes in admin panel take effect immediately — coordinate with any active promotions
- handoff_dependencies: Products table populated with active=true records and correct prices before customer session begins

### Cell: Handoff during Browse Products
This cell describes the perspective of "Handoff" during the "Browse Products" stage.
State: draft. Locked: no.

Trigger: Customer lands on product listing page with language preference set from s1. Prerequisite: Language preference set; active products loaded from Supabase products table. Output: Customer has viewed products and selected quantities; cart state held in component state or localStorage. Flows to: Select Date & Fulfillment (s3). Failure recovery: If Supabase product fetch fails, show cached fallback or error state with a retry button.

Actor fields:
- trigger_event: Customer lands on product listing page with language set from s1
- handoff_output: Cart state with at least one item qty > 0; customer ready to select dates and fulfillment
- handoff_timing: After customer selects quantities and clicks Continue
- upstream_actor: Land & Language Select stage (s1)
- downstream_actor: Select Date & Fulfillment stage (s3)
- failure_recovery: Supabase product fetch fails → show error state with retry button; display last cached product data if available
- validation_rules: At least one product must have qty > 0 before proceeding to s3
- prerequisite_data: Language preference from s1; active products loaded from Supabase products table
- communication_method: Client-side cart state (React state or localStorage); Supabase REST API
- data_retention_policy: Cart state held in session; cleared after order confirmed or page abandoned
- upstream_dependencies: Supabase products table populated; product photos in Supabase Storage
- prerequisite_data_detail: Language preference; Supabase products table with active=true records

### Cell: Engineering during Browse Products
This cell describes the perspective of "Engineering" during the "Browse Products" stage.
State: draft. Locked: no.

API: GET /api/products → Database client query: SELECT * FROM products WHERE active = true ORDER BY display_order. DB table: products (id, name_en, name_es, description_en, description_es, price_per_day, stock_total, photo_url, active). Product photos: Cloud storage bucket 'product-images' (admin-uploadable). Real-time qty cap (if dates selected): GET /api/availability?product_id=X&date_start=Y&date_end=Z → SUM booked qty for overlapping confirmed orders, subtract from stock_total. ENV: Database URL, Database anonymous key. Error states: fetch fails → error banner + retry button; empty product list → 'No products available' empty state.

Notes: Products seeded in DB before launch; photos uploaded to cloud storage. Max qty = stock_total minus SUM of booked qty for overlapping date ranges with non-cancelled orders. Product photos must be uploaded to cloud storage; photo_url must be updated in products table. Products fetch fails → show error banner + retry; empty products table → show empty state; image load fails → show placeholder. Product list load < 1s; availability query < 300ms. Track product view events per session for analytics.

Actor fields:
- assumptions: Products seeded in DB before launch; photos uploaded to Supabase Storage
- data_inputs: Language preference from localStorage; Supabase products table query
- entry_point: Customer lands on /products page
- data_outputs: Product cards rendered with name, price, description in correct language; quantity selectors with real-time max cap
- task_objective: Display product catalog with live availability caps per product per date
- friction_points: Stale availability if dates change and availability not re-fetched
- success_criteria: All active products displayed; qty selectors cap at real-time available stock
- information_needs: products table: id, name_en, name_es, description_en, description_es, price_per_day, stock_total, photo_url
- tools_and_systems: Next.js page; Supabase JS client; Supabase Storage for product images
- decisions_required: None — automated render
- output_deliverable: Product catalog page with dynamic quantity limits
- audit_logging_needs: Track product view events per session for analytics
- business_rules_logic: Max qty = stock_total minus SUM of booked qty for overlapping date ranges with non-cancelled orders
- employee_constraints: Product photos must be uploaded to Supabase Storage; photo_url must be updated in products table
- handoff_dependencies: Language preference from s1
- security_permissions: Supabase anon key (public read); RLS: customers can read active products only
- system_service_owner: Product catalog service
- error_states_edge_cases: Products fetch fails → show error banner + retry; empty products table → show empty state; image load fails → show placeholder
- performance_requirements: Product list load < 1s; availability query < 300ms
- data_storage_requirements: Read: products table; order_items + orders tables for availability calc
- api_integration_dependencies: GET /api/products → supabase.from('products').select('*').eq('active',true); GET /api/availability?product_id&date_start&date_end → SUM booked qty for overlapping orders

### Cell: Metrics during Browse Products
This cell describes the perspective of "Metrics" during the "Browse Products" stage.
State: draft. Locked: no.

Product view rate: % of sessions where all 3 product types are viewed — target > 70%. Add-to-cart rate: % of sessions with at least one qty > 0 selected — target > 60%. Drop-off rate: % who leave from product page without proceeding — target < 30%. Product fetch error rate: Supabase fetch failures < 0.1%. Availability query latency: < 300ms. Most-viewed product: track to inform inventory planning. Most-abandoned qty selector: flag if customers repeatedly max out then back off (signals high demand for specific dates).

Actor fields:
- csat_score: 8
- error_rate: 2
- stage_health: 8
- drop_off_rate: 25
- completion_rate: 75
- volume_frequency: Every session that passes s1
- sla_compliance_rate: 98
- avg_time_to_complete: 2

### Cell: Product Manager during Browse Products
This cell describes the perspective of "Product Manager" during the "Browse Products" stage.
State: draft. Locked: no.

User Story: As a customer planning a party, I want to see all available rental products with clear photos, pricing, and real-time availability, so I can quickly select the right items without guessing or calling the business.

Acceptance Criteria:
- All 3 product types displayed with photos, names (bilingual), descriptions, and price per day
- Quantity selector shows min 1 and max = real-time available stock for selected dates
- Product cards show seating capacity, dimensions, and ideal use case
- Availability updates dynamically when dates change
- Page loads in < 1 second on mobile

Value: Increases browse-to-add conversion by making product selection fast and confident; reduces inbound calls asking 'what do you have?'

Actor fields:
- assumptions: Customers know what they want (chairs/tables) but may need help with quantity and style selection
- pain_points: No current funnel analytics on browse behavior — flying blind on where customers get stuck
- entry_trigger: Customer begins browsing product catalog
- tools_systems: Product analytics (Mixpanel/Amplitude) to track browse-to-add conversion; heatmaps to see what customers click
- task_objective: Optimize product discovery and selection — ensure customers can quickly find what they need and understand pricing/availability
- friction_points: If catalog is overwhelming or search is weak, customers may abandon before adding items
- success_criteria: Browse-to-add conversion > 80%; average time to first add < 90 seconds
- information_needs: Which products are most viewed vs. most added? Where do customers drop off? Are filters/search being used?
- decisions_required: Should we add product recommendations? Improve search/filter UX? Show popular items first?
- output_deliverable: Product catalog UX improvement roadmap; A/B test plan for layout variations
- employee_constraints: Product images and descriptions are managed by business owner — PM cannot change content directly
- handoff_dependencies: Engineering for catalog UX improvements; Marketing for product photography and descriptions

### Cell: XU Designer during Browse Products
This cell describes the perspective of "XU Designer" during the "Browse Products" stage.
State: draft. Locked: no.

UX Designer owns the product card layout, quantity selector component, and availability feedback states. Three cards must work in a 3-column grid (desktop) and single-column scroll (mobile). Product photos require a fixed aspect ratio (4:3) with a consistent placeholder for failed loads. Quantity +/− buttons must be minimum 44×44px tap targets. Low-stock badge must be visually urgent but not alarming. Out-of-stock state replaces the selector with a clear disabled message. Service zone reference card must be scannable on mobile.

Actor fields:
- assumptions: Business owner will supply consistent product photos; stock threshold of 15 is a stable business rule
- pain_points: Business owner uploading portrait photos into a landscape card breaking layout; quantity selector tap targets too small on mobile causing mis-taps
- entry_trigger: Customer proceeds from language selection and lands on the product catalog
- tools_systems: Figma (card and selector components), Tailwind CSS grid, Lucide icons (AlertTriangle, Plus, Minus)
- task_objective: Design product cards with bilingual content, quantity selector, availability states (in-stock, low-stock, out-of-stock), and service zone reference card — all mobile-first
- friction_points: Product images with inconsistent aspect ratios breaking card alignment; quantity buttons too small for mobile tap accuracy; Spanish product descriptions overflowing card bounds
- success_criteria: Cards render consistently across all 3 breakpoints; +/− buttons meet 44px tap target; low-stock badge visible and legible; placeholder renders on image failure; page load < 1s
- information_needs: Maximum bilingual product name and description lengths; image asset dimensions from business owner; stock threshold for low-stock badge trigger (currently < 15 units)
- decisions_required: Card image aspect ratio; low-stock badge colour and animation (currently red pulse); grid breakpoints for 1-col / 2-col / 3-col; quantity input width for 3-digit numbers
- output_deliverable: Product card component spec (all states: default, selected, low-stock, out-of-stock); service zone card spec; mobile product grid layout
- employee_constraints: Product images must be reviewed at the defined aspect ratio before upload — non-conforming photos will break card layout
- handoff_dependencies: Product photo URLs and dimensions from backend; final EN/ES product copy from business owner before component sizing

### Cell: Description during Select Date & Fulfillment
This cell describes the perspective of "Description" during the "Select Date & Fulfillment" stage.
State: draft. Locked: no.

Customer selects rental start date and return date via a date picker. Available stock quantities update in real time on date change — preventing overbooking. Customer chooses delivery or store pickup. Delivery requires a valid address validated against up to 5 admin-configured service zones; delivery fee is shown by zone. Pickup displays store address and configurable pickup window hours. Out-of-zone addresses are blocked with a bilingual message.

### Cell: Customer during Select Date & Fulfillment
This cell describes the perspective of "Customer" during the "Select Date & Fulfillment" stage.
State: draft. Locked: no.

Customer picks their rental dates using a date picker. Quantity limits update immediately — they can see at a glance if items are low on availability. They choose delivery or pickup with a simple toggle. Delivery: they type their address and see the delivery fee estimate. If outside the service zone, they see a friendly bilingual message explaining the limitation. Pickup: store address and pickup hours are shown clearly. No surprises.

Actor fields:
- emotions: Practical — locking in logistics before committing to pay
- assumptions: Assumes delivery is available to their address; may not know zone limits
- entry_trigger: Customer proceeds from product selection
- expected_output: Dates selected, fulfillment chosen, delivery fee shown or pickup confirmed
- friction_points: Address rejected by zone validation; date availability confusing; delivery fee higher than expected
- information_needs: Service area coverage, delivery fee, pickup hours and address
- channel_touchpoint: Date picker + fulfillment toggle (mobile-first)
- decisions_required: Rental start and return dates; delivery or pickup; delivery address if applicable
- acceptance_criteria: Valid dates selected; fulfillment confirmed; no overbooking risk; delivery fee visible

### Cell: Internal (Staff) during Select Date & Fulfillment
This cell describes the perspective of "Internal (Staff)" during the "Select Date & Fulfillment" stage.
State: draft. Locked: no.

N/A — Staff does not act during date and fulfillment selection. Delivery zone boundaries and fees are pre-configured by admin in the settings panel. Real-time availability is computed automatically from the Supabase orders table — no manual staff input needed.

Actor fields:
- emotions: Passive — zones pre-configured
- assumptions: Delivery zones and fees are configured correctly in the settings table before go-live
- pain_points: Outdated zone config causes valid addresses to be incorrectly rejected or out-of-zone addresses to be accepted
- entry_trigger: Customer selects dates and fulfillment — zone validation and availability checks run automatically against admin-configured settings
- tools_systems: Admin settings panel (delivery zones, fees, pickup hours config)
- task_objective: Maintain accurate delivery zone boundaries, fees, and pickup hours in admin settings so availability and zone validation run correctly without staff involvement
- expected_output: Zone validation and availability checks run automatically
- friction_points: Zone boundaries not updated when service area expands or contracts; pickup hours out of date
- success_criteria: Zone validation accepts valid addresses and blocks out-of-zone addresses correctly; correct delivery fee shown per zone
- information_needs: How to update zone polygon boundaries, per-zone flat fees, and store pickup window hours in admin settings
- channel_touchpoint: Admin settings panel (pre-session configuration)
- decisions_required: None during customer session — zones and fees configured in advance via admin panel
- output_deliverable: N/A — staff output is pre-session zone and fee configuration
- acceptance_criteria: N/A — staff does not act at this stage
- employee_constraints: Zone boundary changes affect live customer sessions immediately — test after any update
- handoff_dependencies: settings.delivery_zones and settings.pickup_hours persisted in settings table before customer session begins

### Cell: Handoff during Select Date & Fulfillment
This cell describes the perspective of "Handoff" during the "Select Date & Fulfillment" stage.
State: draft. Locked: no.

Trigger: Customer moves to date/fulfillment step via Continue button or inline progression. Prerequisite: At least one item with qty > 0 in cart. Output: Rental dates confirmed; fulfillment type selected; delivery address validated against zones OR pickup confirmed; real-time stock availability verified for selected dates. Flows to: Order Summary & Checkout (s4). Failure recovery: Out-of-zone address → block with bilingual message; date conflict → update qty max; Supabase availability query fails → show error + retry.

Actor fields:
- trigger_event: Customer moves to date/fulfillment step with at least one item in cart
- handoff_output: Rental dates confirmed; fulfillment type selected; delivery address zone-validated with fee OR pickup confirmed; real-time stock verified for dates
- handoff_timing: After customer confirms dates, fulfillment, and address; clicks Continue to checkout
- upstream_actor: Browse Products stage (s2)
- downstream_actor: Order Summary & Checkout stage (s4)
- failure_recovery: Out-of-zone address → block with bilingual message; availability conflict → reduce qty cap; Supabase query fails → show error + retry
- validation_rules: Start date must be >= today; return date must be > start date; delivery address must match a configured zone; at least one item must still be available on selected dates
- prerequisite_data: Cart items with quantities; language preference; Supabase availability API accessible
- communication_method: Supabase availability API; Google Maps Geocoding API for zone validation
- data_retention_policy: Dates and fulfillment stored in session state; passed forward to checkout
- upstream_dependencies: Supabase orders + order_items tables; settings table with delivery_zones; Google Maps API key configured
- prerequisite_data_detail: Cart items; dates; fulfillment type; delivery zones config from settings table

### Cell: Engineering during Select Date & Fulfillment
This cell describes the perspective of "Engineering" during the "Select Date & Fulfillment" stage.
State: draft. Locked: no.

Availability API: GET /api/availability → SELECT SUM(order_items.quantity) FROM order_items JOIN orders ON order_items.order_id = orders.id WHERE order_items.product_id = $1 AND orders.rental_start <= $end AND orders.rental_end >= $start AND orders.status != 'cancelled'. Zone validation: POST /api/validate-zone { address: string } → geocode via Maps Geocoding API, compare lat/lng against zone polygons stored in settings table (key: delivery_zones). Returns { zone_id, delivery_fee } or { error: 'out_of_zone' }. DB read: orders, order_items, settings. Error states: zone validation fail → block + bilingual message; availability query fail → show error + retry; invalid date range → inline validation.

Notes: Delivery zones configured in settings table as JSON polygon array; zip fallback table available. Availability = stock_total - SUM(booked_qty) for overlapping non-cancelled orders. Zone validation uses polygon containment check on geocoded lat/lng. Maps API key must be set; delivery_zones must be valid JSON in settings table. Out-of-zone address → block + bilingual message; invalid date range → inline error; database availability fails → retry; Maps API fails → fallback to zip-code zone matching. Availability query < 300ms; zone validation < 500ms. Log zone rejection events with address (anonymized) for service area analysis.

Actor fields:
- assumptions: Delivery zones configured in settings table as JSON polygon array; zip fallback table available
- data_inputs: Cart items + quantities; selected date range; fulfillment type; delivery address string
- entry_point: Customer proceeds from product selection to date/fulfillment step
- data_outputs: Confirmed dates; fulfillment type; zone_id + delivery_fee (delivery) or pickup confirmed; updated availability caps per product
- task_objective: Lock dates, validate fulfillment choice, confirm real-time availability, return delivery fee or pickup details
- friction_points: Google Maps API quota exceeded; zone polygon config malformed in settings
- success_criteria: Dates valid; fulfillment confirmed; no overbooking risk; delivery fee shown or pickup confirmed
- information_needs: settings.delivery_zones JSON; settings.pickup_hours; settings.store_address
- tools_and_systems: Next.js; date picker component; Supabase availability API; Google Maps Geocoding API
- decisions_required: None — automated validation
- output_deliverable: Locked dates, fulfillment type, delivery fee or pickup details passed to s4
- audit_logging_needs: Log zone rejection events with address (anonymized) for service area analysis
- business_rules_logic: Availability = stock_total - SUM(booked_qty) for overlapping non-cancelled orders. Zone validation uses polygon containment check on geocoded lat/lng.
- employee_constraints: NEXT_PUBLIC_GOOGLE_MAPS_API_KEY must be set; delivery_zones must be valid JSON in settings table
- handoff_dependencies: Cart state from s2; language preference from s1
- security_permissions: Supabase anon key for availability; NEXT_PUBLIC_GOOGLE_MAPS_API_KEY for geocoding
- system_service_owner: Availability and zone validation service
- error_states_edge_cases: Out-of-zone address → block + bilingual message; invalid date range → inline error; Supabase availability fails → retry; Maps API fails → fallback to zip-code zone matching
- performance_requirements: Availability query < 300ms; zone validation < 500ms
- data_storage_requirements: Read: orders, order_items, settings(delivery_zones)
- api_integration_dependencies: GET /api/availability?product_id&date_start&date_end; POST /api/validate-zone {address} → geocode + zone polygon check; returns {zone_id, delivery_fee} or {error:'out_of_zone'}

### Cell: Metrics during Select Date & Fulfillment
This cell describes the perspective of "Metrics" during the "Select Date & Fulfillment" stage.
State: draft. Locked: no.

Date selection completion rate: % who pick valid dates and proceed — target > 80%. Delivery vs pickup split: % choosing each — track to inform delivery capacity planning. Zone rejection rate: % of delivery attempts blocked — target < 10%; high rate signals need to show service area map earlier. Availability conflict rate: % of sessions where real-time qty update reduces customer's selected amount — flag if > 5% (indicates high-demand date pressure). Fulfillment selection drop-off: % who abandon at this step — target < 20%.

Actor fields:
- csat_score: 7
- error_rate: 8
- stage_health: 7
- drop_off_rate: 20
- completion_rate: 80
- volume_frequency: Every session with cart items
- sla_compliance_rate: 92
- avg_time_to_complete: 3

### Cell: Product Manager during Select Date & Fulfillment
This cell describes the perspective of "Product Manager" during the "Select Date & Fulfillment" stage.
State: draft. Locked: no.

User Story: As a customer, I want to select my rental dates and choose delivery or pickup with instant feedback on availability and delivery eligibility, so I don't waste time configuring an order that can't be fulfilled.

Acceptance Criteria:
- Date picker allows selection of rental start and return dates
- Real-time availability check updates quantity caps immediately on date change
- Delivery address validated against service zones; out-of-zone addresses blocked with clear bilingual message
- Delivery fee shown by zone; pickup shows store address and hours
- No overbooking risk — inventory allocated only after payment confirmed

Value: Reduces late-stage abandonment by surfacing delivery eligibility and availability upfront; prevents customer frustration from rejected orders.

Actor fields:
- assumptions: Customers don't know the service area before starting; real-time inventory check is accurate and fast
- pain_points: No current tracking of out-of-zone attempts or date unavailability abandonment — can't measure impact of improvements
- entry_trigger: Customer selects rental date and enters delivery address
- tools_systems: Google Maps API for delivery zone validation; Supabase for real-time inventory availability; funnel analytics to track drop-off rate at this stage
- task_objective: Minimize drop-off at date/address selection — ensure customers know service area upfront and see real-time availability
- friction_points: Late-stage rejection (after product selection) if address is out of zone or date is unavailable — high frustration and abandonment risk
- success_criteria: Out-of-zone rejection rate < 10%; date unavailability drop-off < 15%; average time to complete this stage < 60 seconds
- information_needs: What % of customers enter out-of-zone addresses? How many abandon after seeing 'unavailable' for their date?
- decisions_required: Should we show delivery zone map upfront (before product selection)? Should we allow waitlist for sold-out dates?
- output_deliverable: PRD for delivery zone map feature; real-time availability UX spec; A/B test plan for zone disclosure timing
- employee_constraints: Delivery zones are business-defined and may change seasonally — must be admin-configurable, not hardcoded
- handoff_dependencies: Engineering to implement zone map and real-time availability API; Operations to define delivery zones in admin config

### Cell: XU Designer during Select Date & Fulfillment
This cell describes the perspective of "XU Designer" during the "Select Date & Fulfillment" stage.
State: draft. Locked: no.

UX Designer owns the date picker, delivery/pickup toggle, address/ZIP inputs, and zone validation feedback components. Date picker must use native input[type=date] on mobile to avoid heavy library overhead — styled to match the design system. Delivery/pickup is a segmented control (not a dropdown). ZIP validation feedback must be inline, immediate, and bilingual — never a modal. Out-of-zone rejection must not feel like a dead end: pickup must be visible as an alternative immediately below the error.

Actor fields:
- assumptions: Native date input provides acceptable UX on iOS and Android; ZIP code is sufficient for zone validation without full address geocoding
- pain_points: iOS auto-zoom on small-font inputs breaking the mobile layout mid-form; zone rejection with no recovery path causing high drop-off at this stage
- entry_trigger: Customer proceeds from product selection with at least one item in cart
- tools_systems: Figma (form components, date picker, segmented control), native HTML input[type=date], Tailwind CSS, inline error state patterns
- task_objective: Design date selection, fulfillment toggle, address/ZIP form, and zone validation feedback — all mobile-first with inline error states and bilingual copy
- friction_points: Heavy date picker libraries causing slow load on mobile; out-of-zone error with no clear alternative causes abandonment; date input fields triggering iOS auto-zoom if font < 16px
- success_criteria: Date picker works on iOS and Android without custom library; zone validation feedback appears inline within 500ms; pickup alternative visible immediately on rejection; no iOS auto-zoom on any input
- information_needs: Min/max date constraints from business rules; ZIP error message strings in EN and ES; delivery fee display format per zone; pickup store address and hours for display
- decisions_required: Native vs. custom date picker; segmented control vs. radio buttons for delivery/pickup; ZIP error inline vs. toast; how prominently to surface pickup as fallback after zone rejection
- output_deliverable: Date picker component spec; fulfillment segmented control spec; inline ZIP validation error states (valid, invalid, out-of-zone); mobile form layout redline
- employee_constraints: All form inputs must use 16px minimum font size to prevent iOS Safari auto-zoom — no exceptions
- handoff_dependencies: Zone validation API response shape (zone_id, delivery_fee, error) must be finalised before designing feedback states; EN/ES error strings confirmed

### Cell: Description during Order Summary & Checkout
This cell describes the perspective of "Description" during the "Order Summary & Checkout" stage.
State: draft. Locked: no.

Customer reviews an itemized order summary: each product × quantity × days × price per day. Delivery fee (or 'Free Pickup' label) is shown. Texas sales tax (8.25%, configurable) is calculated and displayed. Grand total is shown. Customer enters full name, phone number, and email address. Payment method is selected — Stripe card or 'Pay in Person' (pickup orders only, admin-togglable). Deposit mode shows partial amount due now if admin has configured a deposit %.

### Cell: Customer during Order Summary & Checkout
This cell describes the perspective of "Customer" during the "Order Summary & Checkout" stage.
State: draft. Locked: no.

Customer sees everything laid out before paying: each item, how many days, price breakdown, delivery fee or free pickup label, tax, and total. They fill in name, phone, and email. They choose card payment or Pay in Person (if eligible). If deposit mode is active, they see 'Reserve with $X now — balance due at delivery/pickup.' They feel fully in control before committing.

Actor fields:
- emotions: Reviewing carefully before paying — looking for hidden fees
- assumptions: Expects total to match what was shown earlier; trusts tax is correct
- entry_trigger: Dates and fulfillment confirmed from previous step
- expected_output: Customer understands full cost and has entered valid contact info
- friction_points: Deposit logic unclear; tax line confusing; form validation errors
- information_needs: Itemized breakdown, deposit vs full pay, what happens after payment
- channel_touchpoint: Order summary and checkout form (mobile-first)
- decisions_required: Confirm order details; choose payment method; enter contact info
- acceptance_criteria: All form fields valid; customer has reviewed total and proceeding to pay

### Cell: Internal (Staff) during Order Summary & Checkout
This cell describes the perspective of "Internal (Staff)" during the "Order Summary & Checkout" stage.
State: draft. Locked: no.

N/A — Staff does not act during checkout form completion. Admin controls the 'Pay in Person' toggle, deposit percentage, and tax rate via the settings panel. These settings take effect immediately across the storefront without code changes.

Actor fields:
- emotions: Passive — checkout config pre-set
- assumptions: tax_rate, deposit_percentage, and pay_in_person_enabled are correctly set in settings table before go-live
- pain_points: Misconfigured deposit % causes customers to be undercharged or overcharged at booking; Pay in Person left on causes cash-handling issues
- entry_trigger: Customer views order summary — tax, deposit, and payment options pulled from settings table in real time
- tools_systems: Admin settings panel (deposit_percentage, tax_rate, pay_in_person_enabled config)
- task_objective: Maintain correct checkout configuration (deposit %, tax rate, Pay in Person toggle) in admin settings so the order summary reflects current business policy
- expected_output: Checkout options reflect current admin configuration
- friction_points: Pay in Person toggle left enabled when business is not prepared to accept cash; deposit % not updated after policy change
- success_criteria: Order summary shows correct tax, correct deposit amount (if applicable), and correct payment options per current admin config
- information_needs: How to update deposit %, toggle Pay in Person on/off, and adjust tax rate in the admin settings panel
- channel_touchpoint: Admin settings panel (pre-session configuration)
- decisions_required: None during customer session — all checkout config set in advance via admin panel
- output_deliverable: N/A — staff output is pre-session checkout configuration
- acceptance_criteria: N/A — staff does not act at this stage
- employee_constraints: Changes to deposit % or Pay in Person toggle take effect on the next customer session immediately — communicate changes to team
- handoff_dependencies: settings.tax_rate, settings.deposit_percentage, settings.pay_in_person_enabled persisted before customer session begins

### Cell: Handoff during Order Summary & Checkout
This cell describes the perspective of "Handoff" during the "Order Summary & Checkout" stage.
State: draft. Locked: no.

Trigger: Dates and fulfillment confirmed from s3. Prerequisite: Cart items, dates, fulfillment type, delivery address (if applicable). Output: Validated order draft with all line items, fees, tax, and total; customer contact info (name, phone, email) collected and validated. Flows to: Payment Processing (s5). Failure recovery: Form validation errors shown inline; tax/fee calculation error → show error state with retry.

Actor fields:
- trigger_event: Dates and fulfillment confirmed from s3; customer proceeds to order summary
- handoff_output: Validated order draft: all line items, delivery fee, tax, total; customer contact info (name, phone, email) collected and validated
- handoff_timing: After customer completes contact form and clicks Pay / Place Order
- upstream_actor: Select Date & Fulfillment stage (s3)
- downstream_actor: Payment Processing stage (s5)
- failure_recovery: Form validation errors shown inline; settings fetch fails for tax/deposit → use hardcoded defaults and show warning
- validation_rules: Name required; phone must be 10-digit US number; email must be valid format; all order items must still reflect current availability
- prerequisite_data: Cart items, qty, dates, fulfillment type, delivery address + zone + fee (or pickup flag), language preference
- communication_method: Client-side form validation; settings read from Supabase via API route
- data_retention_policy: Order draft held in session until payment confirmed or abandoned
- upstream_dependencies: Supabase settings table; Stripe.js loaded with publishable key
- prerequisite_data_detail: Cart + dates + fulfillment from s3; tax_rate, deposit_percentage, pay_in_person_enabled from settings table

### Cell: Engineering during Order Summary & Checkout
This cell describes the perspective of "Engineering" during the "Order Summary & Checkout" stage.
State: draft. Locked: no.

Tax: subtotal * parseFloat(settings.tax_rate ?? '0.0825'). Delivery fee: from zone validation result in s3. Deposit: if settings.deposit_percentage > 0 → charge_amount = total * (deposit_pct / 100); else charge_amount = total. Pay in Person: shown only if settings.pay_in_person_enabled = true AND fulfillment = 'pickup'. Form validation: name required; phone regex /^[0-9]{10}$/; email regex RFC 5322. Payment SDK loaded via script tag with publishable key. No payment API call yet — PaymentIntent created in s5. DB read: settings (tax_rate, deposit_percentage, pay_in_person_enabled). ENV: Payment processor publishable key.

Notes: Tax rate, deposit %, and pay_in_person toggle are configured in settings table before launch. charge_amount = total * deposit_pct if deposit_pct > 0, else total. Tax = subtotal * tax_rate. Pay in Person shown only if pay_in_person_enabled = true AND fulfillment = pickup. Payment processor publishable key must be set; all settings keys must exist in settings table. Settings fetch fails → use hardcoded defaults (tax=0.0825) + show warning; form validation errors → inline messages; payment SDK load fails → show error + retry. Settings fetch < 200ms; form validation < 50ms client-side. Log order draft creation with items + total for funnel analytics.

Actor fields:
- assumptions: Tax rate, deposit %, and pay_in_person toggle are configured in settings table before launch
- data_inputs: Cart items, dates, fulfillment, zone delivery_fee; settings: tax_rate, deposit_percentage, pay_in_person_enabled
- entry_point: Customer arrives at order summary page with dates + fulfillment confirmed
- data_outputs: Order draft: line items, delivery fee, tax, grand total, charge_amount; customer contact info (name, phone, email) validated
- task_objective: Render itemized order summary with correct pricing; collect and validate customer contact info; prepare for payment
- friction_points: Missing settings keys cause calculation errors; Stripe.js blocked by ad-blockers
- success_criteria: Order total calculated correctly; all form fields validated; customer ready to pay
- information_needs: settings: tax_rate, deposit_percentage, pay_in_person_enabled; Stripe publishable key
- tools_and_systems: Next.js; Supabase settings read; Stripe.js loaded via next/script
- decisions_required: None — customer makes decisions; system validates inputs
- output_deliverable: Validated order draft + customer contact info ready for s5 payment call
- audit_logging_needs: Log order draft creation with items + total for funnel analytics
- business_rules_logic: charge_amount = total * deposit_pct if deposit_pct > 0, else total. Tax = subtotal * tax_rate. Pay in Person shown only if pay_in_person_enabled = true AND fulfillment = pickup.
- employee_constraints: NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY must be set; all settings keys must exist in settings table
- handoff_dependencies: Cart, dates, fulfillment, delivery_fee from s3; language from s1
- security_permissions: Supabase anon key for settings read; Stripe publishable key (public)
- system_service_owner: Checkout and order summary service
- error_states_edge_cases: Settings fetch fails → use hardcoded defaults (tax=0.0825) + show warning; form validation errors → inline messages; Stripe.js load fails → show error + retry
- performance_requirements: Settings fetch < 200ms; form validation < 50ms client-side
- data_storage_requirements: Read: settings table (tax_rate, deposit_percentage, pay_in_person_enabled)
- api_integration_dependencies: GET /api/settings?keys=tax_rate,deposit_percentage,pay_in_person_enabled → settings table lookup; Stripe.js loaded with NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY

### Cell: Metrics during Order Summary & Checkout
This cell describes the perspective of "Metrics" during the "Order Summary & Checkout" stage.
State: draft. Locked: no.

Checkout form completion rate: % who complete all required fields and proceed to payment — target > 75%. Cart abandonment rate at summary stage: target < 25% (industry benchmark). Average order value: tracked per session and over time. Pay in Person selection rate: % of eligible pickup orders choosing this option — informs cash handling prep. Deposit confusion rate: proxy metric — track if customers abandon specifically at payment method selection (signals unclear deposit messaging). Form error rate: % of submissions with validation errors — target < 10%.

Actor fields:
- csat_score: 7
- error_rate: 10
- stage_health: 7
- drop_off_rate: 25
- completion_rate: 75
- volume_frequency: Every session that passes s3
- sla_compliance_rate: 90
- avg_time_to_complete: 3

### Cell: Product Manager during Order Summary & Checkout
This cell describes the perspective of "Product Manager" during the "Order Summary & Checkout" stage.
State: draft. Locked: no.

User Story: As a customer ready to book, I want to see a complete itemized order summary with all costs (items, delivery, tax, total) before I pay, so I can review everything and feel confident there are no hidden fees.

Acceptance Criteria:
- Itemized breakdown: each product × quantity × days × price per day
- Delivery fee or 'Free Pickup' label shown
- Texas sales tax (8.25%) calculated and displayed
- Grand total shown clearly
- Deposit mode shows partial amount due now vs. balance due later (if configured)
- Customer enters name, phone, email with inline validation
- Payment method selection: Stripe card or Pay in Person (pickup only, if enabled)

Value: Increases checkout conversion by eliminating sticker shock and pricing confusion; builds trust through transparency.

Actor fields:
- assumptions: Customers expect to pay a deposit upfront and remainder later; pricing transparency reduces abandonment
- pain_points: No current data on why customers abandon at checkout — need exit surveys or session replay to diagnose
- entry_trigger: Customer reviews order summary and proceeds to checkout
- tools_systems: Checkout funnel analytics; A/B testing platform for pricing display variations; Stripe for payment method options
- task_objective: Maximize checkout conversion — ensure pricing is transparent, deposit vs. full-pay logic is clear, and cart review is frictionless
- friction_points: Sticker shock if total cost (with tax, delivery, deposit) is not clear earlier; confusion over deposit vs. full-pay timing
- success_criteria: Order summary to payment initiation conversion > 85%; checkout abandonment rate < 15%
- information_needs: What % of customers abandon at order summary vs. payment entry? Do customers understand deposit vs. full-pay? Are taxes/fees a surprise?
- decisions_required: Should deposit % be more prominent? Should we offer payment plans? Should we show total cost earlier in the funnel?
- output_deliverable: Checkout UX optimization roadmap; pricing transparency A/B test plan; payment options evaluation
- employee_constraints: Deposit % and pricing rules are business-defined and may vary by product or season — must be admin-configurable
- handoff_dependencies: Engineering for checkout UX improvements; Finance/Owner to define deposit policy and pricing rules

### Cell: XU Designer during Order Summary & Checkout
This cell describes the perspective of "XU Designer" during the "Order Summary & Checkout" stage.
State: draft. Locked: no.

UX Designer owns the order summary layout, pricing transparency components, deposit/full-pay toggle, and checkout form. The summary must clearly separate each line item (subtotal / delivery / tax / deposit / total) with visual hierarchy. Deposit vs. full-pay logic requires an explicit callout: 'Pay $X now — $Y due at delivery/pickup' to prevent abandonment from confusion. All form inputs must be 16px minimum font. Card inputs must feel secure (lock icon, muted background). The submit button must visually disable during processing to block double-tap.

Actor fields:
- assumptions: Customers will read the deposit callout if it's visually prominent; Stripe Elements can be styled sufficiently to match the design system
- pain_points: Deposit vs. full-pay toggle designed without dollar amounts causes customer confusion and support calls; card input visually inconsistent with the rest of the form breaking trust
- entry_trigger: Customer proceeds from date and fulfillment confirmation with valid cart and delivery details
- tools_systems: Figma (summary and form components), Stripe Elements appearance API (card input styling), Tailwind CSS, Lucide icons (CreditCard, Lock)
- task_objective: Design itemised order summary, deposit/full-pay payment toggle, contact form, card entry form, and processing/error states — all mobile-first with clear pricing transparency
- friction_points: Sticker shock if total with tax, delivery, and deposit is not clearly explained before this stage; deposit vs. full-pay toggle confusing if not labelled with dollar amounts; card inputs feeling insecure causing abandonment
- success_criteria: All line items visible without scrolling on mobile; deposit callout immediately understandable without explanation; form validation errors appear inline; processing state prevents double-tap; card inputs styled to match design system
- information_needs: All pricing line item labels in EN/ES; deposit explanation copy in both languages; Stripe Elements available styling properties; card decline error message strings
- decisions_required: Deposit callout design (banner vs. inline vs. tooltip); card input visual treatment (embedded vs. distinct card section); processing button state (spinner vs. progress bar); error state placement (inline vs. toast)
- output_deliverable: Order summary component spec (all states); deposit/full-pay toggle spec with dollar-amount labels; checkout form spec with inline validation states; Stripe Elements style spec
- employee_constraints: Card input styling is constrained by Stripe Elements API — custom fonts and some colour properties may not be available; test in Stripe test mode before final design sign-off
- handoff_dependencies: Final pricing copy in EN/ES from PM; Stripe Elements appearance API constraints from Engineering; form validation error messages confirmed

### Cell: Description during Payment Processing
This cell describes the perspective of "Description" during the "Payment Processing" stage.
State: draft. Locked: no.

Stripe PaymentIntent is created and card payment is processed. Deposit % or full amount is charged based on admin config. 'Pay in Person' orders bypass Stripe entirely. On success: order record is written to Supabase (orders + order_items tables), inventory is allocated for the selected dates, and a unique order number is generated (format: BPR-XXXXXX). New order alert email fires to admin immediately.

### Cell: Customer during Payment Processing
This cell describes the perspective of "Customer" during the "Payment Processing" stage.
State: draft. Locked: no.

Customer enters card details in the Stripe payment form. If deposit mode is on, they clearly see what they are being charged now vs. later. On success, payment goes through smoothly and they are taken to the confirmation page. If the card is declined, they see a clear, friendly error and a retry option — no confusing codes or jargon. Pay in Person customers skip payment entirely and proceed directly to confirmation.

Actor fields:
- emotions: Slightly anxious — entering card details and hoping it goes through
- assumptions: Expects payment to process quickly and smoothly
- entry_trigger: Customer submits checkout form
- expected_output: Payment confirmed; redirected to confirmation page
- friction_points: Card declined with unclear error; slow payment processing; confusion about deposit amount charged
- information_needs: What is being charged now; what happens if payment fails
- channel_touchpoint: Stripe payment form embedded in checkout page
- decisions_required: Enter card details or select Pay in Person; confirm charge amount
- acceptance_criteria: Payment succeeds or clear retry shown; customer lands on confirmation page

### Cell: Internal (Staff) during Payment Processing
This cell describes the perspective of "Internal (Staff)" during the "Payment Processing" stage.
State: draft. Locked: no.

Staff receives a new order alert email immediately after successful payment. The alert includes: customer name, phone, email, items ordered, quantities, rental dates, fulfillment type (delivery address or pickup), and total charged. Staff does not need to take any action for standard orders — the alert is for situational awareness. Staff may intervene if a customer calls with a payment question or if an anomaly is flagged.

Actor fields:
- emotions: Alert — watching for new order notifications
- assumptions: ADMIN_EMAIL is correctly set in environment variables; SendGrid new-order template is configured and active
- pain_points: Alert lands in spam causing staff to miss new bookings; alert email misconfigured showing wrong order data; ops dashboard not accessible on mobile
- entry_trigger: New order alert email received from SendGrid immediately after successful Stripe payment and order record creation
- tools_systems: Admin email inbox, SendGrid new-order alert template, ops dashboard (order list view)
- task_objective: Acknowledge incoming new order alert; verify order appears in ops dashboard; intervene only if payment anomaly or customer calls with issue
- expected_output: Staff is aware of new booking; order appears in ops dashboard
- friction_points: Alert email lands in spam folder; ADMIN_EMAIL env var misconfigured; staff misses alert during high-volume periods
- success_criteria: New order alert received in admin inbox within 30 seconds of booking; order visible in ops dashboard immediately
- information_needs: Customer name, phone, email, items ordered, quantities, rental dates, fulfillment type (delivery address or pickup), total charged
- channel_touchpoint: Email (admin inbox)
- decisions_required: No action required for standard orders — alert is awareness only; intervene if payment looks anomalous or customer contacts staff
- output_deliverable: Staff awareness of new booking — no output artifact required for standard orders
- acceptance_criteria: New order alert received < 30s after booking; order visible in ops dashboard
- employee_constraints: Staff must not manually edit order records in Supabase directly — use ops dashboard only; all standard orders require zero manual intervention
- handoff_dependencies: Successful Stripe charge + order record written to Supabase before alert fires; SENDGRID_API_KEY and ADMIN_EMAIL env vars set

### Cell: Handoff during Payment Processing
This cell describes the perspective of "Handoff" during the "Payment Processing" stage.
State: draft. Locked: no.

Trigger: Customer submits checkout form with payment method selected. Prerequisite: Validated order draft + customer contact info from s4; Stripe.js loaded with publishable key. Output: Stripe PaymentIntent created and confirmed; order record written to Supabase (orders + order_items); inventory allocated for selected dates; order_number generated; admin new-order alert email sent. Flows to: Order Confirmation (s6). Failure recovery: Stripe declined → friendly retry prompt; Supabase write fails → log error, show retry, do NOT double-charge; inventory conflict at write time → cancel, notify customer to re-select dates.

Actor fields:
- trigger_event: Customer submits payment form (card or Pay in Person selection)
- handoff_output: Stripe PaymentIntent confirmed; order record in Supabase (orders + order_items); inventory allocated; order_number generated; admin new-order alert sent
- handoff_timing: Immediately after Stripe payment confirmation webhook or direct client confirmation
- upstream_actor: Order Summary & Checkout stage (s4)
- downstream_actor: Order Confirmation stage (s6)
- failure_recovery: Card declined → friendly error + retry; Supabase write fails → log error, show retry, do NOT re-charge; inventory conflict at write → rollback + show 'item no longer available for these dates'
- validation_rules: PaymentIntent must be in 'succeeded' state before order write; order_number must be unique; inventory must not be overallocated
- prerequisite_data: Validated order draft from s4; Stripe publishable key loaded; customer contact info collected
- communication_method: Stripe API (server-side); Supabase REST API (server-side); SendGrid API for admin alert
- data_retention_policy: Order record persists permanently in Supabase; Stripe payment_id stored on order record
- upstream_dependencies: Stripe account configured; Supabase service role key available; SendGrid API key set; ADMIN_EMAIL env var set
- prerequisite_data_detail: Order draft; Stripe secret key; Supabase service role key; ADMIN_EMAIL; SENDGRID_API_KEY

### Cell: Engineering during Payment Processing
This cell describes the perspective of "Engineering" during the "Payment Processing" stage.
State: draft. Locked: no.

POST /api/create-payment-intent: payment processor SDK create payment intent with amount: charge_amount_cents, currency: 'usd', metadata: { order_draft } → returns clientSecret. Client-side: payment processor SDK confirm card payment with clientSecret and card element. On success: POST /api/create-order → INSERT INTO orders (...) RETURNING id; INSERT INTO order_items (...); UPDATE inventory allocation. Order number: 'BPR-' + Date.now().toString(36).toUpperCase() + randomInt(1000,9999). Admin alert: email service send with to: ADMIN_EMAIL, templateId: 'new-order-alert', dynamicTemplateData: order. ENV: Payment processor secret key, Payment processor publishable key, Database service role key, Email service API key, ADMIN_EMAIL. Error states: card declined → payment error message → user-friendly display; Database INSERT fails → 500 response → do NOT retry payment charge; inventory conflict → rollback + notify customer.

Notes: Payment account in live mode for production; webhook endpoint configured for payment events. order_number format: 'BPR-' + base36 timestamp + 4-digit random. Use payment processor idempotency keys to prevent double charges on retry. Payment processor secret key must never be in client-side code; use server-side API routes only. Card declined → payment error message → user-friendly message; Database INSERT fails → log, show retry, do NOT re-charge; inventory conflict at write → cancel order, refund PaymentIntent, show 'item no longer available'; payment API timeout → idempotency key prevents double charge. PaymentIntent create < 2s; order write < 1s; total s5 flow < 5s. Log payment attempt, outcome, and payment_id on order record.

Actor fields:
- assumptions: Stripe account in live mode for production; webhook endpoint configured for payment events
- data_inputs: Order draft from s4; card payment method from Stripe Elements; charge_amount; customer contact info
- entry_point: Customer submits payment form
- data_outputs: Stripe PaymentIntent confirmed; order record in Supabase; order_items records; order_number generated; admin alert sent
- task_objective: Create PaymentIntent, confirm payment, write order to DB, allocate inventory, alert admin
- friction_points: Race condition on inventory at write time for high-demand dates; Stripe webhook vs direct confirmation timing
- success_criteria: PaymentIntent status = succeeded; order record created; inventory allocated; admin alerted
- information_needs: STRIPE_SECRET_KEY; SUPABASE_SERVICE_ROLE_KEY; SENDGRID_API_KEY; ADMIN_EMAIL all set in env
- tools_and_systems: Stripe Node.js SDK (server-side); Supabase service role client; SendGrid API; Next.js API routes
- decisions_required: None — automated
- output_deliverable: order_id, order_number passed to s6 confirmation page
- audit_logging_needs: Log payment attempt, outcome, and Stripe payment_id on order record
- business_rules_logic: order_number format: 'BPR-' + base36 timestamp + 4-digit random. Use Stripe idempotency keys to prevent double charges on retry.
- employee_constraints: STRIPE_SECRET_KEY must never be in client-side code; use server-side API routes only
- handoff_dependencies: Order draft + customer contact info from s4; Stripe publishable key loaded in s4
- security_permissions: STRIPE_SECRET_KEY server-side only; SUPABASE_SERVICE_ROLE_KEY server-side only; never exposed to client
- system_service_owner: Payment processing and order creation service
- error_states_edge_cases: Card declined → stripe.error.message → user-friendly message; Supabase INSERT fails → log, show retry, do NOT re-charge; inventory conflict at write → cancel order, refund PaymentIntent, show 'item no longer available'; Stripe API timeout → idempotency key prevents double charge
- performance_requirements: PaymentIntent create < 2s; order write < 1s; total s5 flow < 5s
- data_storage_requirements: Write: orders table (1 row); order_items table (n rows per cart item)
- api_integration_dependencies: POST /api/create-payment-intent → stripe.paymentIntents.create({amount, currency:'usd', idempotency_key}); POST /api/create-order → INSERT orders + order_items; POST /api/notify-admin → SendGrid dynamic template

### Cell: Metrics during Payment Processing
This cell describes the perspective of "Metrics" during the "Payment Processing" stage.
State: draft. Locked: no.

Payment success rate: target > 95%. Payment failure rate: % of attempts that fail — track by failure type (declined, network, 3DS). Retry success rate: % of failed payments that succeed on retry — target > 50%. Order write success rate: Supabase INSERT success > 99.9%. Inventory conflict rate at write time: target < 0.1% (indicates overbooking risk — escalate immediately if rising). End-to-end payment latency: PaymentIntent create + confirm + order write < 5 seconds. Admin alert delivery: new order email delivered to admin < 30 seconds after order creation.

Actor fields:
- csat_score: 8
- error_rate: 5
- stage_health: 8
- drop_off_rate: 5
- completion_rate: 95
- volume_frequency: Every checkout attempt
- sla_compliance_rate: 95
- avg_time_to_complete: 1

### Cell: Product Manager during Payment Processing
This cell describes the perspective of "Product Manager" during the "Payment Processing" stage.
State: draft. Locked: no.

User Story: As a customer, I want my payment to process quickly and securely with clear error messages if something goes wrong, so I can complete my booking without frustration or fear of being double-charged.

Acceptance Criteria:
- Stripe PaymentIntent created and confirmed in < 5 seconds
- Card declined errors shown in user-friendly language with retry option
- No double-charging on retry (idempotency keys enforced)
- Pay in Person customers skip payment and proceed directly to confirmation
- Order record written to Supabase only after successful payment
- Inventory allocated for selected dates; order number generated (format: BPR-XXXXXX)
- Admin receives new order alert email within 30 seconds

Value: Maximizes payment success rate (> 95%); reduces payment abandonment and support calls about failed charges.

Actor fields:
- assumptions: Stripe is reliable but card declines are customer-side; retry UX can recover some failures
- pain_points: No current tracking of payment failure reasons or retry behavior — can't prioritize improvements
- entry_trigger: Customer submits payment via Stripe
- tools_systems: Stripe dashboard for payment success/failure analytics; error tracking (Sentry or similar) for payment API issues
- task_objective: Ensure payment success rate > 95% — minimize payment failures, retries, and customer frustration
- friction_points: Payment failures due to card declines, network issues, or Stripe API errors — customer may abandon if retry is not smooth
- success_criteria: Payment success rate > 95%; retry-to-success rate > 50%; payment failure abandonment < 5%
- information_needs: What % of payments fail? What are the top failure reasons (card decline, network timeout, etc.)? How many customers retry vs. abandon?
- decisions_required: Should we add alternative payment methods (PayPal, Venmo, ACH)? Should we implement retry logic for transient failures?
- output_deliverable: Payment failure analysis report; alternative payment methods evaluation; retry UX spec
- employee_constraints: Stripe is the only payment processor — cannot switch without major eng effort
- handoff_dependencies: Engineering to implement retry logic and alternative payment methods; Stripe support for failure diagnostics

### Cell: XU Designer during Payment Processing
This cell describes the perspective of "XU Designer" during the "Payment Processing" stage.
State: draft. Locked: no.

UX Designer owns the payment processing state, card decline error UX, Pay in Person confirmation flow, and the transition to the confirmation page. The processing state must be full-screen or prominent enough that the customer clearly knows something is happening — spinner + 'Processing your booking…' message. Card decline errors must use plain, friendly language in EN/ES — never raw Stripe error codes. Pay in Person selection must feel as complete and confident as a successful card payment. Transition to confirmation must be smooth (no jarring hard reload).

Actor fields:
- assumptions: Customers will retry on decline if the error message is friendly and the retry path is clear; < 5s processing latency is acceptable with a visible loading state
- pain_points: Stripe error codes surfaced directly to customers in early builds causing support calls; processing animation stopping before API resolves causing double-submission
- entry_trigger: Customer submits the checkout form with payment method selected
- tools_systems: Figma (loading and error state components), Stripe Elements (card input), CSS transitions for success animation, Lucide icons (CheckCircle, AlertTriangle)
- task_objective: Design payment processing state, card decline error messages, Pay in Person flow, and success transition animation — ensuring customers feel secure and informed throughout
- friction_points: Raw Stripe error codes shown to customer ('card_error: do_not_honor') causing confusion and distrust; processing spinner disappears too quickly causing customer to tap submit again
- success_criteria: Processing state visible and stable for full duration of API call; no raw error codes visible in any state; Pay in Person flow leads to confirmation page identically to card payment; transition to confirmation page is smooth
- information_needs: Stripe error code to friendly message mapping in EN/ES; Pay in Person flow confirmation copy; processing average latency (target < 5s) to calibrate loading animation duration
- decisions_required: Full-screen overlay vs. button-state-only processing indicator; specific friendly error messages per Stripe decline type (card_declined, insufficient_funds, expired_card); Pay in Person CTA copy and confirmation design
- output_deliverable: Payment processing overlay spec; card decline error state designs (per error type, in EN/ES); Pay in Person confirmation flow spec; success transition animation spec
- employee_constraints: All error message copy must be reviewed by PM before implementation — no dev-written error strings in production
- handoff_dependencies: Stripe error code list from Engineering; Pay in Person enabled/disabled state from settings API; idempotency key behaviour confirmed so retry UX is safe to design

### Cell: Description during Order Confirmation
This cell describes the perspective of "Description" during the "Order Confirmation" stage.
State: draft. Locked: no.

Customer sees order confirmation number displayed prominently on screen. SendGrid email and Twilio SMS are triggered automatically in the customer's chosen language (EN or ES). Email includes: order number, items, dates, fulfillment details, total paid, and business contact info. Delivery confirmations include expected delivery window. Pickup confirmations include store address, pickup hours, and instruction to bring confirmation number and ID.

### Cell: Customer during Order Confirmation
This cell describes the perspective of "Customer" during the "Order Confirmation" stage.
State: draft. Locked: no.

Customer sees a confirmation page with their order number in large, easy-to-read text. Within seconds, they receive an SMS and email in their language. The message tells them everything they need to know — order number, what they rented, dates, fulfillment details, and a phone number if they have questions. They feel taken care of and do not need to call. Delivery customers know their window; pickup customers know exactly where to go and what to bring.

Actor fields:
- emotions: Relieved and satisfied — order is confirmed
- assumptions: Expects to receive confirmation immediately; will check email and SMS
- entry_trigger: Successful payment or Pay in Person selection confirmed
- expected_output: Order number on screen; email and SMS received in chosen language
- friction_points: Confirmation page not clear; notifications delayed or missing; wrong language
- information_needs: Order number, what to do next, contact info for questions
- channel_touchpoint: Confirmation page + email + SMS
- decisions_required: None — passive receipt of confirmation
- acceptance_criteria: Order number displayed; email received < 60s; SMS received < 60s; both in correct language

### Cell: Internal (Staff) during Order Confirmation
This cell describes the perspective of "Internal (Staff)" during the "Order Confirmation" stage.
State: draft. Locked: no.

N/A — Confirmation notifications are fully automated. SendGrid sends the email and Twilio sends the SMS without any staff action. Staff may optionally be CC'd on confirmation emails depending on admin notification settings.

Actor fields:
- emotions: Passive — confirmations are automated
- assumptions: SendGrid and Twilio are configured and operational; 4 SendGrid templates (en_delivery, en_pickup, es_delivery, es_pickup) are created and active
- pain_points: Silent notification failure with no admin alert; customer calls to ask for confirmation because email went to spam
- entry_trigger: N/A — customer confirmation email and SMS fire automatically; staff role is passive monitoring only
- tools_systems: Admin dashboard (notification_log view), SendGrid activity feed, Twilio logs
- task_objective: Monitor notification delivery health via admin dashboard logs; no action required for standard confirmations — all automated
- expected_output: Customer receives email and SMS confirmation without staff involvement
- friction_points: Staff has no visibility into notification failures unless dashboard log is checked; no real-time alert on notification failure by default
- success_criteria: Customer receives email and SMS confirmation without any staff involvement; staff only intervenes if notification failure is flagged
- information_needs: How to access notification delivery logs in admin dashboard; how to identify and respond to SendGrid or Twilio delivery failures
- channel_touchpoint: Notification log in admin dashboard (monitoring only)
- decisions_required: No action for standard confirmations; manually follow up with customer if both email and SMS delivery fail
- output_deliverable: N/A — staff output is passive monitoring; no artifact produced for standard confirmations
- acceptance_criteria: N/A — staff does not act at this stage for standard confirmations
- employee_constraints: Staff must not manually resend confirmations unless both automated channels have failed; check notification_log before contacting customer
- handoff_dependencies: Order record created in s5 with correct customer_email, customer_phone, language, and fulfillment_type before notifications fire

### Cell: Handoff during Order Confirmation
This cell describes the perspective of "Handoff" during the "Order Confirmation" stage.
State: draft. Locked: no.

Trigger: Successful payment + order record created in s5 (or Pay in Person bypass confirmed). Prerequisite: order_id, order_number, customer_email, customer_phone, language, fulfillment details all present in order record. Output: Confirmation page rendered with order number; SendGrid email queued; Twilio SMS sent — both in customer's chosen language. Flows to: Order Lookup & Self-Service (s7) — customer can return any time. Failure recovery: SendGrid failure → retry once → log; Twilio failure → retry once → log; confirmation page renders regardless of notification success.

Actor fields:
- trigger_event: Successful payment + order record created in s5 (or Pay in Person bypass confirmed)
- handoff_output: Confirmation page rendered with order number; SendGrid email sent; Twilio SMS sent — both in customer's chosen language
- handoff_timing: Immediately after order write in s5; notifications fire async (non-blocking)
- upstream_actor: Payment Processing stage (s5)
- downstream_actor: Order Lookup & Self-Service (s7) — customer can return any time; ops team picks up in Map 2
- failure_recovery: SendGrid failure → retry once → log to notification_log; Twilio failure → retry once → log; confirmation page always renders regardless of notification outcome
- validation_rules: Confirmation page must render even if notifications fail; notifications must use correct language and correct template for fulfillment type
- prerequisite_data: order_id, order_number, customer_email, customer_phone, language, fulfillment_type, items, dates, total all present in order record
- communication_method: SendGrid API (email); Twilio API (SMS); Next.js server-side render for confirmation page
- data_retention_policy: Notification send events logged in notification_log table; order record permanent
- upstream_dependencies: SENDGRID_API_KEY; TWILIO_ACCOUNT_SID; TWILIO_AUTH_TOKEN; TWILIO_PHONE_NUMBER; 4 SendGrid templates created (en_delivery, en_pickup, es_delivery, es_pickup)
- prerequisite_data_detail: Complete order record from s5; SendGrid template IDs configured; Twilio number configured

### Cell: Engineering during Order Confirmation
This cell describes the perspective of "Engineering" during the "Order Confirmation" stage.
State: draft. Locked: no.

Confirmation page: server-side render order data from database by order_id (passed via redirect after s5). Email service: POST /api/send-confirmation → email SDK send with to: customer_email, templateId: template_map[language][fulfillment_type], dynamicTemplateData: { order_number, items, dates, total, fulfillment_details, contact_info }. SMS service: POST /api/send-sms → SMS SDK messages create with to: customer_phone, from: SMS_PHONE_NUMBER, body: sms_templates[language][fulfillment_type]. Template map: 4 templates — en_delivery, en_pickup, es_delivery, es_pickup. ENV: Email service API key, SMS account SID, SMS auth token, SMS phone number. Error states: Email/SMS failures → retry once → log to database notification_log table; confirmation page ALWAYS renders regardless of notification outcome.

Notes: 4 email templates created: en_delivery, en_pickup, es_delivery, es_pickup; SMS number verified. Template selection: template_map[customer.language][order.fulfillment_type]. Notification failures are logged but never block the confirmation page render. All 4 email templates must be created before launch; SMS phone number must be SMS-capable. Email/SMS fails → retry once → log to notification_log — page still renders; order_id not found → show error page. Confirmation page render < 1s; notifications sent async (non-blocking); email delivered < 60s; SMS delivered < 60s. Log each notification: type, channel, template_id, language, delivery status, timestamp.

Actor fields:
- assumptions: 4 SendGrid templates created: en_delivery, en_pickup, es_delivery, es_pickup; Twilio number verified
- data_inputs: order_id; order record (fetched server-side); language preference; fulfillment_type
- entry_point: Order created in s5; redirect to /confirmation?order_id=X
- data_outputs: Confirmation page rendered; SendGrid email queued; Twilio SMS sent; notification events logged
- task_objective: Render confirmation page and fire email + SMS notifications in customer's language
- friction_points: Template ID misconfiguration sends wrong language; Twilio number not verified for SMS
- success_criteria: Confirmation page renders; email sent < 60s; SMS sent < 60s; correct language and fulfillment template used
- information_needs: SENDGRID_API_KEY; TWILIO credentials; template IDs for all 4 variants; TWILIO_PHONE_NUMBER
- tools_and_systems: Next.js SSR page; SendGrid Node.js SDK; Twilio Node.js SDK; Supabase service role client
- decisions_required: None — automated
- output_deliverable: Confirmation page shown to customer; email + SMS sent
- audit_logging_needs: Log each notification: type, channel, template_id, language, delivery status, timestamp
- business_rules_logic: Template selection: template_map[customer.language][order.fulfillment_type]. Notification failures are logged but never block the confirmation page render.
- employee_constraints: All 4 SendGrid templates must be created before launch; TWILIO_PHONE_NUMBER must be SMS-capable
- handoff_dependencies: order_id from s5 payment success
- security_permissions: SENDGRID_API_KEY; TWILIO_ACCOUNT_SID; TWILIO_AUTH_TOKEN; TWILIO_PHONE_NUMBER — all server-side only
- system_service_owner: Notification delivery service
- error_states_edge_cases: SendGrid fails → retry once → log to notification_log — page still renders; Twilio fails → retry once → log — page still renders; order_id not found → show error page
- performance_requirements: Confirmation page render < 1s; notifications sent async (non-blocking); email delivered < 60s; SMS delivered < 60s
- data_storage_requirements: Read: orders table; Write: notification_log table (send events)
- api_integration_dependencies: POST /api/send-confirmation → sgMail.send({templateId: template_map[lang][fulfillment]}); POST /api/send-sms → twilio.messages.create({to, from, body: sms_templates[lang][fulfillment]})

### Cell: Metrics during Order Confirmation
This cell describes the perspective of "Metrics" during the "Order Confirmation" stage.
State: draft. Locked: no.

Confirmation page render rate: 100% — must always render regardless of notification status. Email delivery rate: target > 98% (measured via SendGrid delivery events). SMS delivery rate: target > 95% (measured via Twilio delivery webhooks). Notification latency: email + SMS sent < 60 seconds after order creation. Language accuracy: 100% — customer receives confirmation in their selected language (EN or ES). Notification failure rate: log all SendGrid and Twilio failures; alert admin if failure rate > 2% in any rolling 24-hour window.

Actor fields:
- csat_score: 9
- error_rate: 2
- stage_health: 9
- drop_off_rate: 0
- completion_rate: 100
- volume_frequency: Every completed order
- sla_compliance_rate: 98
- avg_time_to_complete: 1

### Cell: Product Manager during Order Confirmation
This cell describes the perspective of "Product Manager" during the "Order Confirmation" stage.
State: draft. Locked: no.

User Story: As a customer who just booked, I want to receive an order confirmation number on screen and via email + SMS in my language within 60 seconds, so I have proof of my booking and know what to do next.

Acceptance Criteria:
- Confirmation page displays order number prominently
- SendGrid email sent in customer's chosen language (EN or ES) with correct fulfillment template (delivery or pickup)
- Twilio SMS sent in customer's chosen language with order number and fulfillment details
- Email and SMS delivered within 60 seconds of booking
- Confirmation includes: order number, items, dates, fulfillment details (delivery window or pickup address + hours), total paid, business contact info
- Confirmation page renders even if email/SMS delivery fails (non-blocking)

Value: Reduces 'did my order go through?' support calls; provides customer with all info needed for pickup or delivery without calling.

Actor fields:
- assumptions: Email + SMS are reliable channels; customers check both; bilingual templates are accurate and complete
- pain_points: No current monitoring of confirmation delivery failures or timing — relying on customer complaints to detect issues
- entry_trigger: Payment succeeds and order is recorded in Supabase
- tools_systems: SendGrid for email delivery; Twilio for SMS delivery; monitoring/alerting for delivery failures
- task_objective: Ensure order confirmation is delivered reliably and quickly (< 60 seconds) via email + SMS in customer's language
- friction_points: If confirmation is delayed or fails, customer may call support or assume order didn't go through — increases support burden
- success_criteria: Email delivery success rate > 98%; SMS delivery success rate > 95%; average delivery time < 60 seconds; zero language mismatch errors
- information_needs: What % of confirmations are delivered successfully? What's average delivery time? Are there language-specific delivery issues?
- decisions_required: Should we add retry logic for failed deliveries? Should we show in-app confirmation as backup? Should we add WhatsApp as a channel?
- output_deliverable: Confirmation delivery monitoring dashboard; retry logic spec; alternative channel evaluation (WhatsApp, in-app)
- employee_constraints: SendGrid and Twilio are the only channels — adding new channels requires eng effort and cost evaluation
- handoff_dependencies: Engineering to implement delivery monitoring and retry logic; SendGrid/Twilio support for delivery diagnostics

### Cell: XU Designer during Order Confirmation
This cell describes the perspective of "XU Designer" during the "Order Confirmation" stage.
State: draft. Locked: no.

UX Designer owns the confirmation page layout and success state. The order number (BPR-XXXXXX) must be the visual hero — large, bold, high-contrast, easy to screenshot or write down. The page must include a 'What happens next' section clearly explaining the delivery window or pickup instructions based on fulfillment type. A prominent 'Look up my order' CTA directs customers to self-service for future status checks. The success state should feel warm and celebratory but appropriate for a local business — not a consumer tech app.

Actor fields:
- assumptions: Customers will screenshot or photograph the confirmation page as their receipt; email may go to spam so the on-screen confirmation must be self-sufficient
- pain_points: Confirmation pages that feel like a receipt stub (just an order number) without next-steps causing customers to call asking what happens now
- entry_trigger: Successful payment or Pay in Person selection confirmed; redirect to confirmation page with order_id
- tools_systems: Figma (confirmation page layout), Tailwind CSS, Lucide icons (CheckCircle, Sparkles, FileText), bilingual copy in both fulfillment variants (delivery / pickup)
- task_objective: Design the confirmation page — order number hero, fulfillment-specific next-steps section, notification delivery status, and self-service lookup CTA — in both EN and ES
- friction_points: Confirmation page that looks generic or temporary makes customers doubt their order went through; missing 'what happens next' section drives support calls asking about delivery times
- success_criteria: Order number visible and legible without scrolling on mobile; fulfillment-specific instructions accurate and complete; 'Look up my order' CTA visible; page renders < 1s; confirmation feels complete even without email/SMS
- information_needs: Order number format (BPR-XXXXXX) for sizing; delivery window copy vs. pickup instruction copy in EN/ES; business contact info for 'questions?' section; email/SMS confirmation sent messaging
- decisions_required: Order number display size and treatment (how big, which font weight); delivery vs. pickup variant layout differences; whether to show email/SMS sent status inline or skip; placement and prominence of 'Look up my order' CTA
- output_deliverable: Confirmation page spec — delivery variant and pickup variant; order number hero component; next-steps section copy and layout; self-service CTA placement
- employee_constraints: Confirmation page must render and feel complete even if email/SMS delivery fails — design must not depend on notification success messaging as the primary receipt
- handoff_dependencies: Order record data shape from Engineering (order number, items, dates, fulfillment details, total paid); fulfillment-specific copy confirmed by PM; business contact info from business owner

### Cell: Description during Order Lookup & Self-Service
This cell describes the perspective of "Description" during the "Order Lookup & Self-Service" stage.
State: draft. Locked: no.

Customer navigates to the order lookup page and enters their email + order number — no account or password needed. A visual status timeline displays current order state: Confirmed → Preparing → Out for Delivery / Ready for Pickup → Delivered / Picked Up → Returned. If the rental start date is more than the admin-configured cancellation window away, a 'Cancel Order' button is shown. Cancellation triggers an automatic Stripe refund and admin alert notification.

### Cell: Customer during Order Lookup & Self-Service
This cell describes the perspective of "Customer" during the "Order Lookup & Self-Service" stage.
State: draft. Locked: no.

Customer returns to the site days later to check their order. They enter email + order number — no account or password needed. They see their status on a clear visual timeline. If they need to cancel and it is within the cancellation window, they see a cancel button and can handle it themselves. If outside the window, they see a clear message explaining why cancellation is no longer available. Entire self-service experience requires zero staff contact for standard cases.

Actor fields:
- emotions: Curious or anxious — checking status before the event
- assumptions: Expects to find order quickly with email and order number
- entry_trigger: Customer navigates to order lookup page after booking
- expected_output: Current order status shown; cancellation option if within window
- friction_points: Can't find order number; status labels unclear; cancellation window expired
- information_needs: Current order status, what each status means, cancellation eligibility
- channel_touchpoint: Order lookup page (mobile-first)
- decisions_required: Whether to cancel order (if within window)
- acceptance_criteria: Order found and status displayed; cancellation flow works if eligible; no staff contact needed

### Cell: Internal (Staff) during Order Lookup & Self-Service
This cell describes the perspective of "Internal (Staff)" during the "Order Lookup & Self-Service" stage.
State: draft. Locked: no.

Staff receives a cancellation alert email if a customer self-cancels via the lookup page. The alert includes: customer name, order number, items, rental dates, and refund amount. Staff does not need to process the cancellation or refund manually — both are handled automatically via the Supabase update and Stripe API. Staff may follow up with the customer if desired.

Actor fields:
- emotions: Alert — receives cancellation alert if customer self-cancels
- assumptions: Cancellation window hours are configured in settings.cancellation_window_hours; STRIPE_SECRET_KEY is valid and active
- pain_points: Silent Stripe refund failure leaves customer expecting a refund that never arrives; staff not alerted until customer disputes charge
- entry_trigger: Cancellation alert email received when customer self-cancels via order lookup page within the allowed window
- tools_systems: Admin email inbox, ops dashboard (order status view), Stripe dashboard (manual refund fallback)
- task_objective: Monitor self-cancellations via cancellation alert email; manually process refund via Stripe dashboard only if automated refund fails; no action required for successful auto-cancellations
- expected_output: Staff is aware of cancellation; order status updated in dashboard; refund processed
- friction_points: Stripe refund failure is silent unless admin checks notification_log; staff unaware of failed refund until customer complains
- success_criteria: Cancellation alert received by staff; order shows 'cancelled' status in ops dashboard; Stripe refund confirmed processed within 5 minutes
- information_needs: Customer name, order number, items cancelled, rental dates, refund amount; Stripe payment_intent ID for manual refund if needed
- channel_touchpoint: Email (admin inbox) + ops dashboard
- decisions_required: No action for successful auto-cancellation + refund; manual Stripe refund required only if automated refund fails and is logged as error
- output_deliverable: Confirmed cancellation in ops dashboard; manual Stripe refund receipt if fallback was needed
- acceptance_criteria: Cancellation alert received; order shows cancelled in dashboard; refund confirmed
- employee_constraints: Do not process manual refunds until automated refund failure is confirmed in logs; use Stripe dashboard only — do not edit order table directly
- handoff_dependencies: Customer cancellation event + Stripe refund attempt logged in notification_log before cancellation alert fires to admin

### Cell: Handoff during Order Lookup & Self-Service
This cell describes the perspective of "Handoff" during the "Order Lookup & Self-Service" stage.
State: draft. Locked: no.

Trigger: Customer navigates to /order-lookup at any time after booking. Prerequisite: Customer has order number and email from confirmation message. Output: Order status displayed; if cancellation requested within window → Supabase status updated to 'cancelled', Stripe refund initiated, admin cancellation alert sent. Flows to: End of customer journey (order state transitions to ops/delivery flow in Map 2). Failure recovery: Invalid email + order number → 'Order not found' message (bilingual); Stripe refund fails → log + alert admin for manual processing; cancellation outside window → block with message.

Actor fields:
- trigger_event: Customer navigates to /order-lookup and submits email + order number
- handoff_output: Order status displayed; if cancellation requested and eligible → status updated to 'cancelled', Stripe refund initiated, admin cancellation alert sent, customer cancellation email sent
- handoff_timing: On demand — customer can access any time after booking
- upstream_actor: Customer (returning to check order)
- downstream_actor: End of customer journey; order state transitions to ops/delivery flow in Map 2
- failure_recovery: Invalid email + order number → bilingual 'not found' message; Stripe refund fails → log + alert admin for manual processing; cancellation outside window → block with bilingual message explaining cutoff
- validation_rules: Email + order number must match an existing order record; cancellation only allowed if (rental_start - now) > cancellation_window_hours
- prerequisite_data: Customer has order number and email from confirmation message
- communication_method: Supabase REST API (order lookup); Stripe API (refund); SendGrid (cancellation emails)
- data_retention_policy: Order status update permanent; refund ID stored on order record
- upstream_dependencies: SUPABASE_SERVICE_ROLE_KEY; STRIPE_SECRET_KEY; SENDGRID_API_KEY; ADMIN_EMAIL; settings.cancellation_window_hours configured
- prerequisite_data_detail: Order record in Supabase; settings.cancellation_window_hours; Stripe payment_id on order if refund needed

### Cell: Engineering during Order Lookup & Self-Service
This cell describes the perspective of "Engineering" during the "Order Lookup & Self-Service" stage.
State: draft. Locked: no.

Order lookup: GET /api/order-lookup?email=X&order_number=Y → SELECT * FROM orders WHERE LOWER(customer_email) = LOWER($email) AND order_number = $order_number. Status timeline: map order.status enum → UI step: confirmed|preparing|out_for_delivery|ready_for_pickup|delivered|picked_up|returned. Cancellation eligibility: (new Date(order.rental_start) - new Date()) > settings.cancellation_window_hours * 3600000. Cancel endpoint: POST /api/cancel-order { order_id } → UPDATE orders SET status='cancelled'; if payment_id → payment processor refunds create with payment_intent: payment_id; email service send cancellation confirmation to customer + admin. ENV: Database service role key, Payment processor secret key, Email service API key, ADMIN_EMAIL. Error states: order not found → bilingual 'not found' message; refund fails → log + alert admin; cancel outside window → block with bilingual message.

Notes: settings.cancellation_window_hours configured in settings table before launch. Cancellation eligible if: (rental_start_timestamp - now_timestamp) > (cancellation_window_hours * 3600000). Email lookup is case-insensitive. cancellation_window_hours must be set in settings table; payment processor secret key server-side only. Email + order_number not found → bilingual 'not found' message; payment refund fails → log + alert admin; cancellation outside window → block + bilingual message; order already cancelled → show cancelled status. Lookup query < 500ms; cancellation + refund < 5s end-to-end. Log all lookup attempts (email + order_number, not full PII); log all cancellation events with refund amount.

Actor fields:
- assumptions: settings.cancellation_window_hours configured in settings table before launch
- data_inputs: customer email + order_number from lookup form
- entry_point: Customer navigates to /order-lookup
- data_outputs: Order record with status displayed; cancellation + refund processed if requested
- task_objective: Allow customer to look up order status and self-cancel within allowed window without staff involvement
- friction_points: Customers losing order number; email case mismatch on lookup; Stripe refund delays
- success_criteria: Order found and status displayed; cancellation processed if eligible; no staff contact needed for standard cases
- information_needs: SUPABASE_SERVICE_ROLE_KEY; STRIPE_SECRET_KEY; SENDGRID_API_KEY; settings.cancellation_window_hours
- tools_and_systems: Next.js page; Supabase service role client; Stripe Node.js SDK; SendGrid SDK
- decisions_required: System determines cancellation eligibility; customer decides whether to cancel
- output_deliverable: Order status page; cancellation + refund if requested
- audit_logging_needs: Log all lookup attempts (email + order_number, not full PII); log all cancellation events with refund amount
- business_rules_logic: Cancellation eligible if: (rental_start_timestamp - now_timestamp) > (cancellation_window_hours * 3600000). Email lookup is case-insensitive.
- employee_constraints: cancellation_window_hours must be set in settings table; STRIPE_SECRET_KEY server-side only
- handoff_dependencies: Order record from s5; settings.cancellation_window_hours
- security_permissions: SUPABASE_SERVICE_ROLE_KEY; STRIPE_SECRET_KEY — server-side only; no customer auth required (security via email + order_number combo)
- system_service_owner: Order lookup and self-service portal
- error_states_edge_cases: Email + order_number not found → bilingual 'not found' message; Stripe refund fails → log + alert admin; cancellation outside window → block + bilingual message; order already cancelled → show cancelled status
- performance_requirements: Lookup query < 500ms; cancellation + refund < 5s end-to-end
- data_storage_requirements: Read: orders, order_items, settings(cancellation_window_hours); Write on cancel: UPDATE orders.status; INSERT notification_log
- api_integration_dependencies: GET /api/order-lookup?email&order_number → supabase SELECT with LOWER() match; POST /api/cancel-order {order_id} → UPDATE status='cancelled' + stripe.refunds.create + SendGrid cancel emails to customer + admin

### Cell: Metrics during Order Lookup & Self-Service
This cell describes the perspective of "Metrics" during the "Order Lookup & Self-Service" stage.
State: draft. Locked: no.

Order lookup success rate: % of lookup attempts that return a valid order — track invalid attempts as a signal customers are losing confirmation numbers. Self-service resolution rate: % of customers who check status and do not subsequently call the business — target > 80% (primary KPI for staff workload reduction). Cancellation rate: % of total orders cancelled via self-service — track trend. Cancellation window compliance: % of cancellation attempts within allowed window vs. outside. Refund processing latency: Stripe refund API < 5 minutes. Lookup page load time: < 2s on mobile.

Actor fields:
- csat_score: 8
- error_rate: 5
- stage_health: 8
- drop_off_rate: 0
- completion_rate: 90
- volume_frequency: On-demand — subset of completed orders
- sla_compliance_rate: 95
- avg_time_to_complete: 1

### Cell: Product Manager during Order Lookup & Self-Service
This cell describes the perspective of "Product Manager" during the "Order Lookup & Self-Service" stage.
State: draft. Locked: no.

User Story: As a customer, I want to check my order status and cancel if needed using just my email and order number, so I can manage my booking without calling the business.

Acceptance Criteria:
- Order lookup page accessible at /order-lookup
- Customer enters email + order number (no account or password required)
- Order status displayed on visual timeline: Confirmed → Preparing → Out for Delivery / Ready for Pickup → Delivered / Picked Up → Returned
- If within cancellation window (admin-configured hours before rental start), 'Cancel Order' button shown
- Cancellation triggers automatic Stripe refund and admin alert notification
- If outside cancellation window, clear bilingual message explains why cancellation is not available
- Lookup works case-insensitive on email

Value: Reduces inbound support calls by 40% (estimated); empowers customers to self-serve order status and cancellations; reduces staff workload.

Actor fields:
- assumptions: Customers prefer self-service over calling; lookup portal is discoverable and easy to use; cancellation window is clearly communicated
- pain_points: No current tracking of self-service usage or support call reasons — can't measure deflection impact
- entry_trigger: Customer needs to check order status, modify, or cancel
- tools_systems: Order lookup portal (webapp); analytics to track lookup usage vs. support call volume; Supabase for order data retrieval
- task_objective: Maximize self-service order lookup usage to reduce inbound support calls by 40%
- friction_points: If lookup is hard to find or requires too much info (order ID, email, phone), customers will call support instead
- success_criteria: Self-service lookup usage > 60% of all order inquiries; support call volume reduction > 40%; lookup-to-resolution rate > 90%
- information_needs: What % of customers use self-service lookup vs. calling support? What are the top reasons for lookup (status check, cancel, modify)?
- decisions_required: Should we add order modification (change date, add items) to self-service? Should we send proactive status updates to reduce lookup need?
- output_deliverable: Self-service portal enhancement roadmap; proactive notification strategy; support deflection analysis
- employee_constraints: Some actions (date changes, item swaps) may require staff approval due to inventory constraints — cannot be fully automated
- handoff_dependencies: Engineering to build/enhance lookup portal; Operations to define what actions are self-service vs. staff-assisted

### Cell: XU Designer during Order Lookup & Self-Service
This cell describes the perspective of "XU Designer" during the "Order Lookup & Self-Service" stage.
State: draft. Locked: no.

UX Designer owns the order lookup form, visual status timeline, cancellation flow, and all error/empty states. The status timeline must use icons + colour + labels — not text alone — for fast visual scanning. Cancel button must be preceded by a confirmation step ('Are you sure? This cannot be undone.') to prevent accidental cancellations. Out-of-window cancellation message must be empathetic, not legalistic — offer contact info for manual requests. All inputs must be 16px minimum to prevent iOS auto-zoom. Lookup form must feel as simple as a hotel reservation lookup.

Actor fields:
- assumptions: Customers will have their order number from the confirmation email/SMS; most lookups are status checks, not cancellations
- pain_points: Text-only status labels requiring careful reading on mobile; accidental cancellations from single-tap cancel buttons in early prototypes; out-of-window messages written in legal language causing customer frustration
- entry_trigger: Customer navigates to order lookup page after booking to check status or manage their order
- tools_systems: Figma (timeline, form, modal components), Tailwind CSS, Lucide icons (CheckCircle, Clock, Truck, Package, AlertTriangle), bilingual copy for all states
- task_objective: Design the order lookup form, status timeline component, cancellation confirmation flow, and all error states (not found, outside window, already cancelled) — mobile-first in EN/ES
- friction_points: Status timeline labels only (no icons or colour) requiring customers to read carefully on mobile; cancel button without confirmation causing accidental cancellations; out-of-window message that feels like a legal rejection instead of helpful guidance
- success_criteria: Status timeline scannable in < 3 seconds on mobile; cancel button requires explicit confirmation; out-of-window message includes contact info; 'not found' state is bilingual and helpful; lookup form prevents iOS auto-zoom
- information_needs: All order status enum values and their display labels in EN/ES; cancellation confirmation copy in both languages; out-of-window message copy; contact info for manual cancellation requests; status colour coding conventions
- decisions_required: Timeline orientation (horizontal scroll vs. vertical steps on mobile); cancel button placement and destructive action treatment (red, confirm modal); how to display partial status (e.g. preparing has no sub-info); empty state design for 'not found'
- output_deliverable: Order lookup form spec; status timeline component spec (all 6 states, both fulfillment types); cancellation confirmation modal spec; error state specs (not found, out-of-window, already cancelled)
- employee_constraints: All destructive actions (cancel) must have a confirmation step — no single-tap irreversible actions allowed in the UI
- handoff_dependencies: Order status enum and transition rules from Engineering; cancellation window hours config from settings API; Stripe refund timing expectations for post-cancel messaging

## Glossary
This section maps the internal keys used in this journey map to their human-readable labels, so that questions referencing either form can be answered.

Stage keys:
- s1: Land & Language Select
- s2: Browse Products
- s3: Select Date & Fulfillment
- s4: Order Summary & Checkout
- s5: Payment Processing
- s6: Order Confirmation
- s7: Order Lookup & Self-Service

Lens keys:
- description: Description
- lens-2: Customer (actor type: customer)
- lens-3: Internal (Staff) (actor type: internal)
- lens-4: Handoff (actor type: handoff)
- lens-5: Engineering (actor type: engineering)
- lens-6: Metrics (actor type: metrics)
- lens-7: Product Manager (actor type: internal)
- lens-8: XU Designer (actor type: internal)
