# CareFirst Incentives JSON Data Dictionary

## About This Document

This is the technical reference for the 13 JSON data files that make up the CareFirst Blue Rewards incentive data feed. Use this document to understand what each file contains, how they relate to each other, and how to combine them for reporting and analysis.

**Companion file:** [`sql/example_queries.sql`](../sql/example_queries.sql) contains 20 ready-to-use SQL queries with detailed comments.

---

## How the Data is Organized

The 13 files form a hierarchy. Program configuration sits at the top; member activity sits at the bottom.

```
PROGRAM CONFIGURATION (what can be earned)
  json_incentives_program_lu ─────────────── One row per program
       │
       ├── json_incentives_program_event_group_lu ── Groups of activities
       │        │
       │        └── json_incentives_program_events_lu ── Individual activities
       │
MEMBER ENROLLMENT (who is enrolled)
       │
       ├── json_programs ────────────────────── One row per member per program
       │        │
       │        │
TRANSACTION HISTORY (what happened)
       │        │
       │        ├── json_earned_history ─────── Points awarded
       │        ├── json_event_history ──────── Raw events (may not earn)
       │        ├── json_redemption_history ──── Points spent
       │        │        │
       │        │        └── json_redemption_history_product ── Product details
       │        │
       │        ├── json_expiration_history ──── Points expired
       │        └── json_manual_adjustment_history ── Admin corrections
       │
REWARD DETAILS (reward-level records)
       │
       ├── json_reward_points ───────────────── Reward instances
       └── json_reward_alternative ──────────── Non-point rewards (co-pay, etc.)

SIMPLE FLAG
       └── json_ag_incentives ───────────────── Is incentives activated? (Y/N)
```

**The central join key is `program_id`** — it connects everything.  
**The member join keys are `member_id` + `member_program_id`** — they connect a specific person to their enrollment and all their transactions.

---

## Common Reporting Scenarios

| Business Question | Files to Use | Join On |
|-------------------|-------------|---------|
| What activities are available in each program? | program_lu + event_group_lu + events_lu | program_id, event_group_id |
| How many members are enrolled and what are their balances? | programs + program_lu | program_id |
| Which activities have the most participation? | earned_history + program_lu | program_id |
| What are members redeeming for? | redemption_history + redemption_history_product | history_id + program_id |
| Why didn't a member earn points? | event_history LEFT JOIN earned_history | history_id + program_id |
| What is the total outstanding point liability? | programs + program_lu | program_id (filter point_balance > 0) |
| How do different employer groups compare? | programs + program_lu | program_id (group by employer_id) |
| What manual corrections have been made? | manual_adjustment_history + program_lu | program_id |
| What points have expired and when? | expiration_history + program_lu | program_id |
| Full audit trail for a member? | UNION of earned + redemption + expiration + adjustment | member_id + member_program_id |
| What non-point rewards (co-pay reductions) were earned? | reward_alternative + reward_points | member_reward_id |

---

## File Descriptions

### Tier 1: Program Configuration

These are lookup/reference files. They define the rules of the program — what can be earned, how much, and under what conditions. They contain no member data.

| File | Grain | Description |
|------|-------|-------------|
| json_incentives_program_lu | 1 row per program | Master program definition. Name, date range, maximum earnable points, dollar value per point, rewards provider. |
| json_incentives_program_event_group_lu | 1 row per event group per program | Logical groupings of activities. Controls gating (one group must complete before another unlocks), repeatability, and group-level point caps. |
| json_incentives_program_events_lu | 1 row per event per program | The individual activities a member can complete to earn. Each event belongs to exactly one event group. Defines points, reward name, earning window dates. |

**Relationship:** Program → has many Event Groups → each has many Events.

### Tier 2: Member Enrollment

| File | Grain | Description |
|------|-------|-------------|
| json_programs | 1 row per member per program | The fact that a member is enrolled in a program. Contains their current point balance, lifetime totals (earned, redeemed, expired), termination status, and employer group. This is your starting point for member-level reporting. |
| json_ag_incentives | 1 row per member | Simple flag indicating whether the member has incentives activated. Members with `incentives_activated = 'false'` will not earn points even if events fire. |

### Tier 3: Transaction History

These files record every point-changing event. Together they form a complete ledger.

| File | Grain | What It Records |
|------|-------|-----------------|
| json_earned_history | 1 row per earning | Points awarded to a member for completing an activity. Contains the point amount, activity name, and timestamps. |
| json_event_history | 1 row per raw event | Every qualifying event the system received — whether or not it resulted in points. Use this to diagnose "why didn't I earn?" questions. |
| json_redemption_history | 1 row per redemption | Points spent by a member in the marketplace. Contains redemption date, amount, and transaction ID. |
| json_expiration_history | 1 row per expiration | Points that expired due to time limits. Contains expiration date and amount. |
| json_manual_adjustment_history | 1 row per adjustment | Administrative corrections — points added or removed manually with a reason/description. |

**Key distinction:** `json_event_history` vs `json_earned_history`
- An event is the raw trigger (e.g., "member completed a screening").
- An earning is the result (e.g., "50 points awarded").
- Events can fail to earn if: the member hit the cap, the group is locked, the event is a duplicate within the repeat window, or the program dates don't cover the event.
- Compare them using `history_id` to find the gap.

### Tier 4: Reward Details

| File | Grain | Description |
|------|-------|-------------|
| json_reward_points | 1 row per reward instance | Detailed record of each reward earned. Includes points, currency label (Dollars/Points), dates, and which event triggered it. |
| json_reward_alternative | 1 row per alternate reward | For programs that offer non-point rewards (specialist co-pay reductions, premium discounts). Contains both the primary and alternate reward names. |
| json_redemption_history_product | 1 row per product per redemption | Marketplace line-item detail. Product name, SKU, quantity, reward type (eGift Card, Blue Rewards Card, etc.), and dollar total. |

---

## Join Keys

| Key | What It Identifies | Where It Appears |
|-----|-------------------|-----------------|
| `program_id` | A specific incentive program | Every file |
| `member_id` | A specific member (numeric) | All member-level files |
| `member_program_id` | A member's enrollment in one program | json_programs, all history files, reward files |
| `event_group_id` | A group of related activities | event_group_lu, events_lu |
| `event_id` | One earnable activity | events_lu, reward_points, reward_alternative |
| `history_id` | One transaction | All history files; links redemption_history to redemption_history_product |
| `member_reward_id` | One reward instance | reward_points, reward_alternative (join these two together) |
| `client_id` | The client/sponsor | json_programs, all history files |
| `collection_id` | Program collection grouping | program_lu, json_programs |
| `employer_id` | Employer/group within the client | json_programs |

---

## How to Join the Files

### Program Structure (Config → Groups → Events)

**When to use:** Understanding what's available in a program, building a program catalog.

```sql
SELECT
    p.program_id, p.program_name, p.max_points,
    eg.event_group_id, eg.event_group_name, eg.locks,
    e.event_id, e.event_description, e.points
FROM json_incentives_program_lu p
JOIN json_incentives_program_event_group_lu eg
    ON p.program_id = eg.program_id
JOIN json_incentives_program_events_lu e
    ON eg.program_id = e.program_id
    AND eg.event_group_id = e.event_group_id
```

### Member Enrollment + Program Details

**When to use:** Reporting on who is enrolled, their balances, and program context.

```sql
SELECT
    m.member_id, m.point_balance,
    m.program_points_earned, m.program_points_redeemed,
    p.program_name, p.max_points
FROM json_programs m
JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id
```

### Earning Transactions + Activity Details

**When to use:** Understanding what members earned and which activity triggered it.

```sql
SELECT
    eh.member_id, eh.event_timestamp,
    eh.event_description, eh.reward AS points_earned,
    e.event_type, eg.event_group_name
FROM json_earned_history eh
JOIN json_incentives_program_events_lu e
    ON eh.program_id = e.program_id
    AND eh.event_identifier = e.event_secondary_identifier
JOIN json_incentives_program_event_group_lu eg
    ON e.program_id = eg.program_id
    AND e.event_group_id = eg.event_group_id
```

### Redemptions + Product Line Items

**When to use:** Reporting on what members are redeeming for in the marketplace.

```sql
SELECT
    rh.member_id, rh.redemption_date, rh.points_redeemed,
    rp.product_name, rp.quantity, rp.total, rp.reward_type
FROM json_redemption_history rh
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id
    AND rh.program_id = rp.program_id
```

### Full Point Lifecycle (Audit Trail)

**When to use:** Reconciling a member's balance, auditing all point-changing events in order.

```sql
SELECT member_id, member_program_id, program_id,
       incentives_timestamp, 'EARNED' AS transaction_type,
       CAST(reward AS INT) AS points_change,
       event_description AS description
FROM json_earned_history
UNION ALL
SELECT member_id, member_program_id, program_id,
       incentives_timestamp, 'REDEEMED',
       -1 * points_redeemed, 'Marketplace Redemption'
FROM json_redemption_history
UNION ALL
SELECT member_id, member_program_id, program_id,
       incentives_timestamp, 'EXPIRED',
       -1 * points_expired, 'Points Expired'
FROM json_expiration_history
UNION ALL
SELECT member_id, member_program_id, program_id,
       incentives_timestamp, 'ADJUSTMENT',
       points_adjusted, description
FROM json_manual_adjustment_history
ORDER BY member_id, member_program_id, incentives_timestamp
```

### Events That Did NOT Earn (Gap Analysis)

**When to use:** Troubleshooting why a member didn't receive points.

```sql
SELECT
    ev.member_id, ev.event_description,
    ev.event_timestamp, ev.event_type
FROM json_event_history ev
LEFT JOIN json_earned_history eh
    ON ev.history_id = eh.history_id
    AND ev.program_id = eh.program_id
WHERE eh.history_id IS NULL
```

---

## Key Concepts

### Balance Reconciliation

The `point_balance` in `json_programs` should equal:

```
program_points_earned - program_points_redeemed - program_points_expired + net(manual_adjustments)
```

If there's a discrepancy, check `json_manual_adjustment_history` for administrative corrections that explain the difference.

### Gating (Locks)

Some event groups require a prerequisite. The `locks` column in `json_incentives_program_event_group_lu` contains the name of the event group that must be completed first. For example, if "Health Coaching" has `locks = 'Health Savings Account (HSA) Agreement'`, a member must complete the HSA agreement before coaching rewards unlock.

### Timestamps: incentives_timestamp vs. event_timestamp

- **incentives_timestamp** — When the system processed the transaction. Use this for "when was the reward given" reporting.
- **event_timestamp** — When the qualifying activity actually occurred. Use this for "when did the member do the activity" reporting.

These can differ by hours or days depending on processing lag.

### Reward Alternatives

Some programs offer non-monetary rewards alongside (or instead of) points — for example, specialist co-pay reductions or premium discounts. These appear in `json_reward_alternative` with both the primary and alternate reward identifiers. Join to `json_reward_points` on `member_reward_id` to see the full picture.

### Data Types

- **Dates** — Stored as varchar in `YYYY-MM-DD HH:MI:SS` format. Cast to DATE or TIMESTAMP for date math.
- **IDs** — MongoDB hex strings (varchar). Always join on exact string match.
- **member_id** — Numeric string representing the Sharecare member identifier.
- **reward** (in earned_history) — Varchar containing the point amount. Cast to INT for arithmetic.

---

## Appendix: Column Definitions

### json_incentives_program_lu

| Column | Type | Description |
|--------|------|-------------|
| program_id | varchar(100) | Unique program identifier (PK) |
| collection_id | varchar(200) | Program collection grouping |
| point_monetary_value | numeric | Dollar value per point (1 = $1/point, 0 = marketplace model) |
| currency | varchar(100) | Currency code (USD) |
| has_marketplace | varchar(5) | Whether program has a redemption marketplace (true/false) |
| rewards_provider | varchar(100) | ADR (third-party marketplace) or SHARECARE (internal fulfillment) |
| reminder_period | varchar(100) | Reminder cadence setting |
| start_date | varchar(121) | Program start date |
| end_date | varchar(121) | Program end date |
| blackout_date | varchar(121) | Date when earning is temporarily suspended |
| program_rules_id | varchar(100) | Internal reference to rules configuration |
| content | varchar(1000) | Program description text |
| expire_days_after_earned | int | Days after earning before points expire |
| expire_days_after_program_end | int | Days after program end before points expire |
| show_reward | varchar(5) | Whether the reward is visible to the member |
| max_points | int | Maximum total points earnable in the program |
| expire_days_after_term | int | Days after member termination before points expire |
| autoredeem | varchar(5) | Whether unredeemed points auto-redeem (true/false) |
| autoredeem_days_after_term | int | Days after termination to trigger auto-redemption |
| autoredeem_min_points | int | Minimum balance required for auto-redemption |
| program_name | varchar(100) | Display name shown to members |
| internal_name | varchar(100) | Internal name used for program identification |
| last_updated_date | varchar(121) | Last modification timestamp |

### json_incentives_program_event_group_lu

| Column | Type | Description |
|--------|------|-------------|
| program_id | varchar(100) | Parent program (FK) |
| event_group_id | varchar(100) | Unique group identifier (PK with program_id) |
| event_group_name | varchar(1000) | Display name of the event group |
| locks | varchar(100) | Name of prerequisite group (must complete first) |
| repeatable | varchar(5) | Whether this group's events can be earned multiple times |
| points | int | Group-level point award (used when group_level_reward = true) |
| group_level_reward | varchar(5) | Award points at the group level rather than per-event |
| repeat_period | varchar(100) | Time window for repeat earning (e.g., yearly, monthly) |
| time_between_periods | varchar(100) | Required gap between earning periods |
| rewards_per_period | int | Maximum number of rewards allowed per period |
| reward_earned_after | int | Number of qualifying events required before reward fires |
| dynamic_start | varchar(1) | Whether the repeat period starts from the first qualifying event |
| max_repeats_per_day | int | Maximum earning occurrences in one day |
| last_updated_date | varchar(121) | Last modification timestamp |

### json_incentives_program_events_lu

| Column | Type | Description |
|--------|------|-------------|
| program_id | varchar(100) | Parent program (FK) |
| event_group_id | varchar(100) | Parent event group (FK) |
| event_id | varchar(100) | Unique event identifier |
| event_type | varchar(100) | Trigger type (e.g., /assessments/completed, /member-tags/changed) |
| event_secondary_identifier | varchar(2000) | Secondary matching key — used to link incoming events to this config |
| event_description | varchar(1000) | Activity name displayed to the member |
| start_date | varchar(121) | Earning window start |
| end_date | varchar(121) | Earning window end |
| blackout_date | varchar(121) | Temporary earning suspension date |
| look_back_period | timestamp | How far back to search for qualifying events |
| min_age | varchar(1) | Age minimum filter |
| max_age | varchar(1) | Age maximum filter |
| gender | varchar(1) | Gender filter |
| conditions | varchar(1) | Health condition filter |
| events_eligible | varchar(1) | Events eligibility filter |
| repeat_period | varchar(100) | Repeat earning window |
| time_between_periods | varchar(100) | Required gap between repeat windows |
| rewards_per_period | int | Max rewards per period |
| reward_earned_after | int | Qualifying events required before earning |
| dynamic_start | varchar(1) | Period starts from first qualifying event |
| max_repeats_per_day | int | Maximum per day |
| points | int | Points awarded for completing this event |
| max_points | int | Maximum points earnable from this event |
| group_level_reward | varchar(5) | Whether this event contributes to group-level reward |
| reward_identifier | varchar(200) | Reward type code |
| reward_name | varchar(200) | Reward type display name |
| tiered_reward_points | varchar(200) | Tiered point structure (if applicable) |
| last_updated_date | varchar(121) | Last modification timestamp |

### json_programs

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member identifier |
| member_program_id | varchar(100) | Unique enrollment record |
| program_id | varchar(100) | Program enrolled in (FK to program_lu) |
| client_id | varchar(100) | Client/sponsor (e.g., HP_SCCAREFIRST) |
| point_balance | int | Current unredeemed balance |
| program_points_earned | int | Lifetime total points earned |
| program_points_redeemed | int | Lifetime total points redeemed |
| program_points_expired | int | Lifetime total points expired |
| termination_aggressive | varchar(5) | Whether aggressive termination applies |
| termination_date | varchar(121) | Date the member was terminated from the program (NULL = active) |
| collection_id | varchar(1000) | Program collection assignment |
| employer_id | varchar(200) | Employer/group identifier within the client |
| last_updated_date | varchar(121) | Last modification timestamp |

### json_ag_incentives

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member identifier |
| incentives_activated | varchar(4) | Whether incentives are turned on for this member (true/false) |

### json_earned_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who earned |
| history_id | varchar(100) | Unique transaction ID |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Enrollment record (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When the system processed the earning |
| event_timestamp | varchar(121) | When the qualifying activity actually occurred |
| event_type | varchar(100) | Trigger type |
| event_identifier | varchar(2000) | Links to event_secondary_identifier in events_lu |
| event_description | varchar(1000) | Activity name displayed to the member |
| reward | varchar(100) | Points/dollars awarded — cast to INT for arithmetic |
| point_balance | int | Member's balance immediately after this transaction |
| manually_fired | varchar(5) | Whether this earning was manually triggered by an administrator |

### json_event_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member the event belongs to |
| history_id | varchar(100) | Unique transaction ID |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Enrollment record (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When the system processed the event |
| event_timestamp | varchar(121) | When the event actually occurred |
| event_type | varchar(100) | Trigger type |
| event_identifier | varchar(2000) | Event matching key |
| event_description | varchar(1000) | Activity name |
| manually_fired | varchar(5) | Whether manually triggered |

### json_redemption_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who redeemed |
| history_id | varchar(100) | Unique transaction ID |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Enrollment record (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When the system processed the redemption |
| event_timestamp | varchar(121) | Event timestamp |
| redemption_date | varchar(121) | Date the redemption was executed |
| points_redeemed | int | Points spent |
| points_word | varchar(100) | Currency label (Dollars, Points, etc.) |
| point_balance | int | Balance after redemption |
| transaction_id | varchar(100) | External transaction reference for reconciliation |

### json_expiration_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member whose points expired |
| history_id | varchar(100) | Unique transaction ID |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Enrollment record (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When the system processed the expiration |
| event_timestamp | varchar(121) | Event timestamp |
| expiration_date | varchar(121) | Date the points expired |
| points_expired | int | Number of points that expired |
| point_balance | int | Balance after expiration |

### json_manual_adjustment_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member affected |
| history_id | varchar(100) | Unique transaction ID |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Enrollment record (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When the adjustment was processed |
| event_timestamp | varchar(121) | Event timestamp |
| points_adjusted | int | Points added (positive) or removed (negative) |
| description | varchar(1000) | Reason for the adjustment |
| point_balance | int | Balance after adjustment |

### json_reward_points

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who earned the reward |
| member_program_id | varchar(100) | Enrollment record (FK) |
| member_reward_id | varchar(100) | Unique reward instance — join to reward_alternative on this |
| program_id | varchar(100) | Program (FK) |
| points | int | Points awarded |
| points_word | varchar(100) | Currency label (Dollars, Points) |
| earned_date | varchar(121) | When the reward was earned |
| activity_date | varchar(121) | When the qualifying activity occurred |
| reward_reason | varchar(1000) | Why the reward was given |
| event_id | varchar(100) | Which event triggered this reward (FK to events_lu.event_id) |

### json_reward_alternative

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who earned |
| member_program_id | varchar(100) | Enrollment record (FK) |
| member_reward_id | varchar(100) | Reward instance — join to reward_points on this |
| program_id | varchar(100) | Program (FK) |
| reward_name | varchar(1000) | Primary reward name |
| reward_identifier | varchar(100) | Primary reward code |
| reward_alternate_name | varchar(1000) | Alternate reward name (e.g., Specialist Copay $5 Reduction) |
| reward_alternate_identifier | varchar(100) | Alternate reward code |
| earned_date | varchar(121) | When the reward was earned |
| activity_date | varchar(121) | When the qualifying activity occurred |
| reward_reason | varchar(1000) | Why the reward was given |
| event_id | varchar(100) | Which event triggered this reward (FK to events_lu) |

### json_redemption_history_product

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who redeemed |
| history_id | varchar(100) | Redemption transaction (FK to redemption_history) |
| program_id | varchar(100) | Program (FK) |
| product_name | varchar(1000) | Product redeemed |
| points | varchar(100) | Points spent on this item |
| total | numeric | Dollar value of this line item |
| quantity | varchar(100) | Quantity |
| sku | varchar(100) | Product SKU |
| reward_type | varchar(100) | Reward category (eGift Card, Blue Rewards Card, etc.) |
| product_id | varchar(100) | Product catalog identifier |
