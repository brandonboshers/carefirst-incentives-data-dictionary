# CareFirst Incentives JSON Data Dictionary

This document describes the 13 incentive-related data files delivered as part of the CareFirst JSON feed. These files contain program configuration, member enrollment, earning/redemption activity, and reward details for the Blue Rewards Incentive Program.

---

## File Descriptions

### Tier 1: Program Configuration (Lookup/Reference)

These files define what can be earned. They do not contain member data.

| File | Grain | Description |
|------|-------|-------------|
| json_incentives_program_lu | 1 row per program | Master program list. Program name, date range, max points, monetary value, rewards provider (ADR=marketplace). |
| json_incentives_program_event_group_lu | 1 row per event group per program | Groups of earnable activities. Controls gating (locks), repeatability, group-level point caps. |
| json_incentives_program_events_lu | 1 row per event per program | Individual earnable activities. Each belongs to an event group. Contains points, reward name, dates. |

### Tier 2: Member Program Enrollment

| File | Grain | Description |
|------|-------|-------------|
| json_programs | 1 row per member per program | Member enrollment. Current point balance, total earned/redeemed/expired, termination status, employer. |
| json_ag_incentives | 1 row per member | Boolean flag: whether the member has incentives activated on their account. |

### Tier 3: Transaction History

One row per transaction event for each member.

| File | Grain | Description |
|------|-------|-------------|
| json_earned_history | 1 row per earning | Points awarded. Includes reward amount, event description, manually_fired flag. |
| json_event_history | 1 row per raw event | Raw events received by the system. May or may not result in points. No reward/points column. |
| json_redemption_history | 1 row per redemption | Points redeemed. Redemption date, amount, transaction ID. |
| json_expiration_history | 1 row per expiration | Points expired. Expiration date, amount expired. |
| json_manual_adjustment_history | 1 row per adjustment | Manual +/- adjustments by admin. Contains reason/description. |

### Tier 4: Reward Details

| File | Grain | Description |
|------|-------|-------------|
| json_reward_points | 1 row per reward earned | Reward-level detail. Points, currency word (Dollars/Points), earned_date, event_id link. |
| json_reward_alternative | 1 row per alt reward | Non-standard rewards (co-pay reductions, premium discounts). Alternate name/identifier. |
| json_redemption_history_product | 1 row per product per redemption | Marketplace line items. Product name, SKU, quantity, reward type, dollar total. |

---

## Join Keys

| Key | Description | Found In |
|-----|-------------|----------|
| program_id | Unique program identifier | All files |
| member_id | Member identifier (numeric) | All member-level files |
| member_program_id | Unique enrollment of a member in a program | json_programs, all history files, reward files |
| event_group_id | Group of related events within a program | event_group_lu, events_lu |
| event_id | Individual earnable event | events_lu, reward_points, reward_alternative |
| history_id | Unique transaction identifier | All history files, redemption_history_product |
| member_reward_id | Unique reward instance | reward_points, reward_alternative |
| client_id | Client/sponsor identifier | json_programs, all history files |
| collection_id | Program collection grouping | program_lu, json_programs |

---

## How to Join the Files

### Program Config to Events

Full program structure: programs → event groups → individual events.

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

### Member Enrollment to Program

```sql
SELECT
    m.member_id, m.point_balance,
    m.program_points_earned, m.program_points_redeemed,
    p.program_name, p.max_points
FROM json_programs m
JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id
```

### Earned History to Event Config

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

### Redemption to Product Details

```sql
SELECT
    rh.member_id, rh.redemption_date, rh.points_redeemed,
    rp.product_name, rp.quantity, rp.total, rp.reward_type
FROM json_redemption_history rh
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id
    AND rh.program_id = rp.program_id
```

### Full Point Lifecycle (Union)

All point-changing events in a single audit trail per member.

```sql
SELECT member_id, member_program_id, program_id,
       incentives_timestamp, 'EARNED' AS type,
       CAST(reward AS INT) AS points_change
FROM json_earned_history
UNION ALL
SELECT member_id, member_program_id, program_id,
       incentives_timestamp, 'REDEEMED',
       -1 * points_redeemed
FROM json_redemption_history
UNION ALL
SELECT member_id, member_program_id, program_id,
       incentives_timestamp, 'EXPIRED',
       -1 * points_expired
FROM json_expiration_history
UNION ALL
SELECT member_id, member_program_id, program_id,
       incentives_timestamp, 'ADJUSTMENT',
       points_adjusted
FROM json_manual_adjustment_history
ORDER BY member_id, incentives_timestamp
```

---

## Common Aggregates

### Points Earned by Event

```sql
SELECT
    p.program_name, eh.event_description,
    COUNT(*) AS times_earned,
    COUNT(DISTINCT eh.member_id) AS unique_members,
    SUM(CAST(eh.reward AS INT)) AS total_points
FROM json_earned_history eh
JOIN json_incentives_program_lu p ON eh.program_id = p.program_id
GROUP BY p.program_name, eh.event_description
ORDER BY total_points DESC
```

### Monthly Earning Trend

```sql
SELECT
    LEFT(eh.incentives_timestamp, 7) AS year_month,
    COUNT(*) AS events,
    COUNT(DISTINCT eh.member_id) AS earners,
    SUM(CAST(eh.reward AS INT)) AS total_points
FROM json_earned_history eh
GROUP BY LEFT(eh.incentives_timestamp, 7)
ORDER BY year_month
```

### Redemption by Product

```sql
SELECT
    rp.product_name, rp.reward_type,
    COUNT(*) AS count,
    COUNT(DISTINCT rh.member_id) AS redeemers,
    SUM(rh.points_redeemed) AS total_points
FROM json_redemption_history rh
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id
    AND rh.program_id = rp.program_id
GROUP BY rp.product_name, rp.reward_type
ORDER BY total_points DESC
```

### Earning Rate by Employer Group

```sql
SELECT
    m.employer_id,
    p.program_name,
    COUNT(DISTINCT m.member_id) AS enrolled_members,
    COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) AS members_with_earnings,
    ROUND(
        COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) * 100.0
        / NULLIF(COUNT(DISTINCT m.member_id), 0), 1
    ) AS earning_rate_pct,
    SUM(m.program_points_earned) AS total_points_earned
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.termination_date IS NULL
GROUP BY m.employer_id, p.program_name
ORDER BY enrolled_members DESC
```

### Activity Completion Funnel

Shows what % of enrolled members completed each activity.

```sql
SELECT
    p.program_name,
    eh.event_description AS activity,
    COUNT(DISTINCT eh.member_id) AS members_completed,
    (SELECT COUNT(DISTINCT member_id) FROM json_programs
     WHERE program_id = eh.program_id AND termination_date IS NULL) AS total_enrolled,
    ROUND(
        COUNT(DISTINCT eh.member_id) * 100.0
        / NULLIF((SELECT COUNT(DISTINCT member_id) FROM json_programs
                  WHERE program_id = eh.program_id AND termination_date IS NULL), 0), 1
    ) AS completion_rate_pct
FROM json_earned_history eh
JOIN json_incentives_program_lu p ON eh.program_id = p.program_id
GROUP BY p.program_name, eh.event_description, eh.program_id
ORDER BY completion_rate_pct DESC
```

### Points Liability Report

Outstanding unredeemed balance by program with estimated dollar value.

```sql
SELECT
    p.program_name,
    p.rewards_provider,
    p.point_monetary_value,
    COUNT(DISTINCT m.member_id) AS members_with_balance,
    SUM(m.point_balance) AS total_outstanding_points,
    CASE WHEN p.point_monetary_value > 0
         THEN SUM(m.point_balance) * p.point_monetary_value
         ELSE NULL END AS estimated_dollar_liability
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.point_balance > 0 AND m.termination_date IS NULL
GROUP BY p.program_name, p.rewards_provider, p.point_monetary_value
ORDER BY total_outstanding_points DESC
```

### Redemption Timing by Month

```sql
SELECT
    p.program_name,
    LEFT(rh.redemption_date, 7) AS redemption_month,
    COUNT(*) AS redemption_count,
    COUNT(DISTINCT rh.member_id) AS unique_redeemers,
    SUM(rh.points_redeemed) AS total_points_redeemed,
    AVG(rh.points_redeemed) AS avg_per_redemption
FROM json_redemption_history rh
JOIN json_incentives_program_lu p ON rh.program_id = p.program_id
GROUP BY p.program_name, LEFT(rh.redemption_date, 7)
ORDER BY p.program_name, redemption_month
```

### Manual Adjustment Audit

```sql
SELECT
    p.program_name,
    ma.description AS adjustment_reason,
    COUNT(*) AS adjustment_count,
    COUNT(DISTINCT ma.member_id) AS members_affected,
    SUM(ma.points_adjusted) AS net_points_adjusted,
    MIN(ma.incentives_timestamp) AS first_adjustment,
    MAX(ma.incentives_timestamp) AS last_adjustment
FROM json_manual_adjustment_history ma
JOIN json_incentives_program_lu p ON ma.program_id = p.program_id
GROUP BY p.program_name, ma.description
ORDER BY ABS(SUM(ma.points_adjusted)) DESC
```

### Expiration by Month

```sql
SELECT
    p.program_name,
    LEFT(ex.expiration_date, 7) AS expiration_month,
    COUNT(*) AS expiration_events,
    COUNT(DISTINCT ex.member_id) AS members_affected,
    SUM(ex.points_expired) AS total_points_expired
FROM json_expiration_history ex
JOIN json_incentives_program_lu p ON ex.program_id = p.program_id
GROUP BY p.program_name, LEFT(ex.expiration_date, 7)
ORDER BY p.program_name, expiration_month
```

### Year-Over-Year Comparison

```sql
SELECT
    p.program_name, eh.event_description,
    COUNT(DISTINCT CASE WHEN LEFT(eh.incentives_timestamp,4) = '2026' THEN eh.member_id END) AS members_2026,
    SUM(CASE WHEN LEFT(eh.incentives_timestamp,4) = '2026' THEN CAST(eh.reward AS INT) ELSE 0 END) AS points_2026,
    COUNT(DISTINCT CASE WHEN LEFT(eh.incentives_timestamp,4) = '2025' THEN eh.member_id END) AS members_2025,
    SUM(CASE WHEN LEFT(eh.incentives_timestamp,4) = '2025' THEN CAST(eh.reward AS INT) ELSE 0 END) AS points_2025
FROM json_earned_history eh
JOIN json_incentives_program_lu p ON eh.program_id = p.program_id
WHERE LEFT(eh.incentives_timestamp,4) IN ('2025','2026')
GROUP BY p.program_name, eh.event_description
ORDER BY p.program_name, points_2026 DESC
```

### Member Engagement Segmentation

Segments members into tiers based on earning vs program max.

```sql
SELECT
    p.program_name,
    CASE
        WHEN m.program_points_earned = 0 THEN 'Inactive'
        WHEN m.program_points_earned < p.max_points * 0.25 THEN 'Low'
        WHEN m.program_points_earned < p.max_points * 0.75 THEN 'Active'
        ELSE 'Power User'
    END AS segment,
    COUNT(*) AS member_count,
    AVG(m.program_points_earned) AS avg_points,
    AVG(m.point_balance) AS avg_balance
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.termination_date IS NULL AND p.max_points > 0
GROUP BY p.program_name,
    CASE
        WHEN m.program_points_earned = 0 THEN 'Inactive'
        WHEN m.program_points_earned < p.max_points * 0.25 THEN 'Low'
        WHEN m.program_points_earned < p.max_points * 0.75 THEN 'Active'
        ELSE 'Power User'
    END
ORDER BY p.program_name, avg_points DESC
```

### Events That Did Not Earn (Gap Analysis)

Find events received by the system that did NOT result in points.

```sql
SELECT
    ev.member_id, ev.program_id,
    ev.event_description, ev.event_timestamp, ev.event_type
FROM json_event_history ev
LEFT JOIN json_earned_history eh
    ON ev.history_id = eh.history_id
    AND ev.program_id = eh.program_id
WHERE eh.history_id IS NULL
ORDER BY ev.member_id, ev.event_timestamp
```

---

## Key Concepts

### event_history vs. earned_history

- **json_event_history** records every qualifying event received (the "trigger").
- **json_earned_history** records when points were actually awarded.
- An event may NOT result in an earning if the member maxed out, the group is locked, or it's a duplicate within a repeat period.
- Compare using `history_id` to find events that did not earn.

### Gating (Locks)

The `locks` column in `json_incentives_program_event_group_lu` indicates a prerequisite. That event group must be completed before this group's rewards unlock.

### Reward Alternatives

Some programs offer non-point rewards (co-pay reductions, premium discounts). `json_reward_alternative` contains these. Join on `member_reward_id` to `json_reward_points`.

### Balance Reconciliation

`json_programs.point_balance` should equal:
```
program_points_earned - program_points_redeemed - program_points_expired + net(manual_adjustments)
```
Check `json_manual_adjustment_history` if there is a discrepancy.

### Data Types

- **Dates**: varchar in `YYYY-MM-DD HH:MI:SS` format. Cast to timestamp/date as needed.
- **IDs**: MongoDB hex strings (varchar). Join on exact string match.
- **member_id**: numeric string (Sharecare member ID).
- **reward** (in earned_history): varchar — cast to INT for sums.

---

## Appendix: Column Definitions

### json_incentives_program_lu

| Column | Type | Description |
|--------|------|-------------|
| program_id | varchar(100) | Unique program identifier (PK) |
| collection_id | varchar(200) | Program collection grouping ID |
| point_monetary_value | numeric | Dollar value per point (1 = $1/point) |
| currency | varchar(100) | Currency code (USD) |
| has_marketplace | varchar(5) | Whether program has a redemption marketplace |
| rewards_provider | varchar(100) | ADR (marketplace) or SHARECARE (internal) |
| reminder_period | varchar(100) | Reminder cadence |
| start_date | varchar(121) | Program start date |
| end_date | varchar(121) | Program end date |
| blackout_date | varchar(121) | Date when earning is suspended |
| program_rules_id | varchar(100) | Reference to program rules config |
| content | varchar(1000) | Program content/description text |
| expire_days_after_earned | int | Days until earned points expire |
| expire_days_after_program_end | int | Days after program end that points expire |
| show_reward | varchar(5) | Whether reward is visible to member |
| max_points | int | Maximum earnable points for the program |
| expire_days_after_term | int | Days after termination that points expire |
| autoredeem | varchar(5) | Whether points auto-redeem |
| autoredeem_days_after_term | int | Days after term to auto-redeem |
| autoredeem_min_points | int | Minimum balance to trigger auto-redeem |
| program_name | varchar(100) | Display name shown to members |
| internal_name | varchar(100) | Internal identifier for the program |
| last_updated_date | varchar(121) | Last time this record was updated |

### json_incentives_program_event_group_lu

| Column | Type | Description |
|--------|------|-------------|
| program_id | varchar(100) | Program this group belongs to (FK) |
| event_group_id | varchar(100) | Unique event group ID (PK with program_id) |
| event_group_name | varchar(1000) | Display name of the event group |
| locks | varchar(100) | Prerequisite event group that must complete first |
| repeatable | varchar(5) | Whether events can be earned multiple times |
| points | int | Group-level point value (if group_level_reward=true) |
| group_level_reward | varchar(5) | Whether reward is at group vs event level |
| repeat_period | varchar(100) | Time window for repeat earning |
| time_between_periods | varchar(100) | Required gap between repeat periods |
| rewards_per_period | int | Max rewards per repeat period |
| reward_earned_after | int | Events required before reward triggers |
| dynamic_start | varchar(1) | Whether repeat period starts from first event |
| max_repeats_per_day | int | Max times earnable in a single day |
| last_updated_date | varchar(121) | Last time this record was updated |

### json_incentives_program_events_lu

| Column | Type | Description |
|--------|------|-------------|
| program_id | varchar(100) | Program this event belongs to (FK) |
| event_group_id | varchar(100) | Event group this event belongs to (FK) |
| event_id | varchar(100) | Unique event ID (PK with program_id + group) |
| event_type | varchar(100) | Trigger type (e.g., /assessments/completed) |
| event_secondary_identifier | varchar(2000) | Secondary key to match incoming events |
| event_description | varchar(1000) | Display name shown to member |
| start_date | varchar(121) | Event earning window start |
| end_date | varchar(121) | Event earning window end |
| blackout_date | varchar(121) | Date earning suspended for this event |
| look_back_period | timestamp | How far back to look for qualifying events |
| min_age | varchar(1) | Minimum age filter |
| max_age | varchar(1) | Maximum age filter |
| gender | varchar(1) | Gender filter |
| conditions | varchar(1) | Condition filter |
| events_eligible | varchar(1) | Events eligibility filter |
| repeat_period | varchar(100) | Repeat earning window |
| time_between_periods | varchar(100) | Gap between repeat windows |
| rewards_per_period | int | Max rewards per period |
| reward_earned_after | int | Events required before earning |
| dynamic_start | varchar(1) | Period starts from first event |
| max_repeats_per_day | int | Max earnable per day |
| points | int | Points awarded for this event |
| max_points | int | Max points earnable for this event |
| group_level_reward | varchar(5) | Reward at group level |
| reward_identifier | varchar(200) | Reward type code |
| reward_name | varchar(200) | Reward type display name |
| tiered_reward_points | varchar(200) | Tiered point values (if applicable) |
| last_updated_date | varchar(121) | Last time this record was updated |

### json_programs

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member identifier |
| member_program_id | varchar(100) | Unique enrollment ID |
| program_id | varchar(100) | Program enrolled in (FK) |
| client_id | varchar(100) | Client/sponsor ID (e.g., HP_SCCAREFIRST) |
| point_balance | int | Current unredeemed point balance |
| program_points_earned | int | Lifetime total points earned |
| program_points_redeemed | int | Lifetime total points redeemed |
| program_points_expired | int | Lifetime total points expired |
| termination_aggressive | varchar(5) | Aggressive termination rules apply |
| termination_date | varchar(121) | Date member was terminated |
| collection_id | varchar(1000) | Program collection assignment |
| employer_id | varchar(200) | Employer/group identifier |
| last_updated_date | varchar(121) | Last time this record was updated |

### json_ag_incentives

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member identifier |
| incentives_activated | varchar(4) | Incentives turned on (true/false) |

### json_earned_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who earned |
| history_id | varchar(100) | Unique transaction ID (PK) |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Member enrollment ID (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When system processed the earning |
| event_timestamp | varchar(121) | When the activity actually occurred |
| event_type | varchar(100) | Type of trigger event |
| event_identifier | varchar(2000) | Matches event_secondary_identifier in events_lu |
| event_description | varchar(1000) | Display name of what was earned |
| reward | varchar(100) | Points/dollars awarded (cast to INT for math) |
| point_balance | int | Member balance after this transaction |
| manually_fired | varchar(5) | Whether manually triggered by admin |

### json_event_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member the event belongs to |
| history_id | varchar(100) | Unique transaction ID (PK) |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Member enrollment ID (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When system processed the event |
| event_timestamp | varchar(121) | When the event actually occurred |
| event_type | varchar(100) | Type of trigger event |
| event_identifier | varchar(2000) | Identifier for the event |
| event_description | varchar(1000) | Display name of the event |
| manually_fired | varchar(5) | Whether manually triggered |

### json_redemption_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who redeemed |
| history_id | varchar(100) | Unique transaction ID (PK) |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Member enrollment ID (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When system processed the redemption |
| event_timestamp | varchar(121) | Event timestamp |
| redemption_date | varchar(121) | Date the redemption was executed |
| points_redeemed | int | Number of points redeemed |
| points_word | varchar(100) | Currency label (Dollars, Points) |
| point_balance | int | Member balance after redemption |
| transaction_id | varchar(100) | External transaction reference |

### json_expiration_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member whose points expired |
| history_id | varchar(100) | Unique transaction ID (PK) |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Member enrollment ID (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When system processed the expiration |
| event_timestamp | varchar(121) | Event timestamp |
| expiration_date | varchar(121) | Date points expired |
| points_expired | int | Number of points expired |
| point_balance | int | Member balance after expiration |

### json_manual_adjustment_history

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member adjusted |
| history_id | varchar(100) | Unique transaction ID (PK) |
| program_id | varchar(100) | Program (FK) |
| member_program_id | varchar(100) | Member enrollment ID (FK) |
| client_id | varchar(100) | Client identifier |
| incentives_timestamp | varchar(121) | When adjustment was processed |
| event_timestamp | varchar(121) | Event timestamp |
| points_adjusted | int | Points added (+) or removed (-) |
| description | varchar(1000) | Reason for the adjustment |
| point_balance | int | Member balance after adjustment |

### json_reward_points

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who earned the reward |
| member_program_id | varchar(100) | Member enrollment ID (FK) |
| member_reward_id | varchar(100) | Unique reward instance ID (PK) |
| program_id | varchar(100) | Program (FK) |
| points | int | Points awarded for this reward |
| points_word | varchar(100) | Currency label (Dollars, Points) |
| earned_date | varchar(121) | Date the reward was earned |
| activity_date | varchar(121) | Date the qualifying activity occurred |
| reward_reason | varchar(1000) | Description of why reward was earned |
| event_id | varchar(100) | Event that triggered this reward (FK to events_lu) |

### json_reward_alternative

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who earned |
| member_program_id | varchar(100) | Member enrollment ID (FK) |
| member_reward_id | varchar(100) | Unique reward instance ID (PK) |
| program_id | varchar(100) | Program (FK) |
| reward_name | varchar(1000) | Primary reward name |
| reward_identifier | varchar(100) | Primary reward code |
| reward_alternate_name | varchar(1000) | Alternate reward name (e.g., Specialist Copay Reduction) |
| reward_alternate_identifier | varchar(100) | Alternate reward code |
| earned_date | varchar(121) | Date the reward was earned |
| activity_date | varchar(121) | Date the qualifying activity occurred |
| reward_reason | varchar(1000) | Description of why reward was earned |
| event_id | varchar(100) | Event that triggered this reward (FK) |

### json_redemption_history_product

| Column | Type | Description |
|--------|------|-------------|
| member_id | varchar(100) | Member who redeemed |
| history_id | varchar(100) | Redemption transaction ID (FK to redemption_history) |
| program_id | varchar(100) | Program (FK) |
| product_name | varchar(1000) | Name of the redeemed product |
| points | varchar(100) | Points spent on this product |
| total | numeric | Dollar value of this line item |
| quantity | varchar(100) | Quantity redeemed |
| sku | varchar(100) | Product SKU |
| reward_type | varchar(100) | Type (eGift Card, Blue Rewards Card, etc.) |
| product_id | varchar(100) | Product catalog identifier |
