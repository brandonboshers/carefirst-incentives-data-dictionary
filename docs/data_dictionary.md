# Blue Rewards Incentive Data - File Guide

## What Is This?

You receive 13 data files that contain everything about your Blue Rewards incentive program. This guide explains what each file is, what the columns mean, and how to connect them together for reporting.

The companion file **[sql/example_queries.sql](../sql/example_queries.sql)** has 20 ready-to-run SQL queries you can copy and use immediately.

---

## The 13 Files at a Glance

The files fall into four categories:

**Program Setup** — What activities are available and how many points they're worth.

| # | File Name | What It Contains |
|---|-----------|-----------------|
| 1 | json_incentives_program_lu | Your incentive programs (name, dates, max points) |
| 2 | json_incentives_program_event_group_lu | Groups of activities within each program |
| 3 | json_incentives_program_events_lu | The individual activities members can complete |

**Member Enrollment** — Who is in the program.

| # | File Name | What It Contains |
|---|-----------|-----------------|
| 4 | json_programs | Each member's enrollment, current balance, and lifetime totals |
| 5 | json_ag_incentives | Whether a member has incentives turned on (yes/no) |

**Transaction History** — What happened (every point earned, spent, expired, or adjusted).

| # | File Name | What It Contains |
|---|-----------|-----------------|
| 6 | json_earned_history | Every time a member earned points |
| 7 | json_event_history | Every activity the system received (even if it didn't earn) |
| 8 | json_redemption_history | Every time a member spent points |
| 9 | json_expiration_history | Every time points expired |
| 10 | json_manual_adjustment_history | Every manual correction by an admin |

**Reward Details** — Specifics about individual rewards and marketplace products.

| # | File Name | What It Contains |
|---|-----------|-----------------|
| 11 | json_reward_points | Detail for each reward earned (points, dates, reason) |
| 12 | json_reward_alternative | Non-point rewards like co-pay reductions |
| 13 | json_redemption_history_product | What product/gift card was redeemed |

---

## How the Files Connect

Think of it like a tree:

1. **Start with a Program** (`json_incentives_program_lu`)
2. Each program has **Activity Groups** (`json_incentives_program_event_group_lu`)
3. Each group has **Individual Activities** (`json_incentives_program_events_lu`)
4. **Members enroll** in programs (`json_programs`)
5. Members **do things** and the system records it (the 5 history files)
6. When they spend points, we know **what they bought** (`json_redemption_history_product`)

The key that connects everything is **`program_id`**. Every file has it.

To connect anything to a specific member, use **`member_id`**.

To connect to a specific member's enrollment in a specific program, use **`member_id` + `member_program_id`**.

---

## Connecting the Files (Join Examples)

### "I want to see what activities are in each program"

Connect: Programs → Activity Groups → Activities

```sql
SELECT
    p.program_name,
    eg.event_group_name   AS activity_group,
    e.event_description   AS activity_name,
    e.points              AS points_earned_for_this
FROM json_incentives_program_lu p
JOIN json_incentives_program_event_group_lu eg
    ON p.program_id = eg.program_id
JOIN json_incentives_program_events_lu e
    ON eg.program_id = e.program_id
    AND eg.event_group_id = e.event_group_id
ORDER BY p.program_name, eg.event_group_name, e.event_description
```

### "I want to see each member's balance and what program they're in"

Connect: Member Enrollment → Program Name

```sql
SELECT
    m.member_id,
    p.program_name,
    m.point_balance          AS current_balance,
    m.program_points_earned  AS total_ever_earned,
    m.program_points_redeemed AS total_ever_spent,
    m.termination_date       AS terminated_on
FROM json_programs m
JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id
ORDER BY p.program_name, m.member_id
```

### "I want to see what members earned and which activity triggered it"

Connect: Earning History → Program Name

```sql
SELECT
    eh.member_id,
    p.program_name,
    eh.event_description  AS activity_completed,
    eh.reward             AS points_earned,
    eh.event_timestamp    AS when_they_did_it,
    eh.incentives_timestamp AS when_points_were_awarded
FROM json_earned_history eh
JOIN json_incentives_program_lu p
    ON eh.program_id = p.program_id
ORDER BY eh.member_id, eh.event_timestamp
```

### "I want to see what members redeemed for"

Connect: Redemption History → Product Details

```sql
SELECT
    rh.member_id,
    rh.redemption_date,
    rh.points_redeemed,
    rp.product_name,
    rp.reward_type,
    rp.total             AS dollar_value
FROM json_redemption_history rh
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id
    AND rh.program_id = rp.program_id
ORDER BY rh.member_id, rh.redemption_date
```

### "I want a complete history of all point changes for a member"

Combine all 4 history files into one timeline:

```sql
SELECT member_id, incentives_timestamp,
       'Earned' AS what_happened,
       CAST(reward AS INT) AS points_change,
       event_description AS details
FROM json_earned_history

UNION ALL

SELECT member_id, incentives_timestamp,
       'Spent', -1 * points_redeemed, 'Marketplace Redemption'
FROM json_redemption_history

UNION ALL

SELECT member_id, incentives_timestamp,
       'Expired', -1 * points_expired, 'Points Expired'
FROM json_expiration_history

UNION ALL

SELECT member_id, incentives_timestamp,
       'Admin Adjustment', points_adjusted, description
FROM json_manual_adjustment_history

ORDER BY member_id, incentives_timestamp
```

---

## Common Reports

### How many members are earning, and how much?

```sql
SELECT
    p.program_name,
    COUNT(DISTINCT eh.member_id)    AS members_who_earned,
    SUM(CAST(eh.reward AS INT))     AS total_points_awarded,
    COUNT(*)                        AS total_earning_events
FROM json_earned_history eh
JOIN json_incentives_program_lu p ON eh.program_id = p.program_id
GROUP BY p.program_name
ORDER BY total_points_awarded DESC
```

### Which activities are most popular?

```sql
SELECT
    eh.event_description            AS activity,
    COUNT(DISTINCT eh.member_id)    AS unique_members,
    COUNT(*)                        AS times_completed,
    SUM(CAST(eh.reward AS INT))     AS total_points
FROM json_earned_history eh
GROUP BY eh.event_description
ORDER BY unique_members DESC
```

### Monthly trend — are members staying engaged?

```sql
SELECT
    LEFT(eh.incentives_timestamp, 7) AS month,
    COUNT(DISTINCT eh.member_id)     AS active_earners,
    SUM(CAST(eh.reward AS INT))      AS total_points
FROM json_earned_history eh
GROUP BY LEFT(eh.incentives_timestamp, 7)
ORDER BY month
```

### Earning rate by employer group

```sql
SELECT
    m.employer_id,
    COUNT(DISTINCT m.member_id) AS enrolled,
    COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) AS earned_at_least_once,
    ROUND(
        COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) * 100.0
        / NULLIF(COUNT(DISTINCT m.member_id), 0), 1
    ) AS earning_rate_pct
FROM json_programs m
WHERE m.termination_date IS NULL
GROUP BY m.employer_id
ORDER BY enrolled DESC
```

### How many points are sitting unredeemed? (Liability)

```sql
SELECT
    p.program_name,
    COUNT(DISTINCT m.member_id)             AS members_with_balance,
    SUM(m.point_balance)                    AS total_unredeemed_points,
    SUM(m.point_balance) * p.point_monetary_value AS estimated_dollar_value
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.point_balance > 0
  AND m.termination_date IS NULL
GROUP BY p.program_name, p.point_monetary_value
ORDER BY total_unredeemed_points DESC
```

### What are the most popular redemption products?

```sql
SELECT
    rp.product_name,
    rp.reward_type,
    COUNT(DISTINCT rh.member_id)  AS unique_redeemers,
    SUM(rh.points_redeemed)       AS total_points_spent,
    SUM(rp.total)                 AS total_dollar_value
FROM json_redemption_history rh
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id
    AND rh.program_id = rp.program_id
GROUP BY rp.product_name, rp.reward_type
ORDER BY total_points_spent DESC
```

### Member segmentation (Power Users vs Inactive)

```sql
SELECT
    CASE
        WHEN m.program_points_earned = 0 THEN 'Inactive - Never Earned'
        WHEN m.program_points_earned < p.max_points * 0.25 THEN 'Low Engagement'
        WHEN m.program_points_earned < p.max_points * 0.75 THEN 'Moderate Engagement'
        ELSE 'High Engagement'
    END AS engagement_tier,
    COUNT(*) AS member_count,
    AVG(m.program_points_earned) AS avg_points_earned,
    AVG(m.point_balance) AS avg_current_balance
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.termination_date IS NULL
  AND p.max_points > 0
GROUP BY
    CASE
        WHEN m.program_points_earned = 0 THEN 'Inactive - Never Earned'
        WHEN m.program_points_earned < p.max_points * 0.25 THEN 'Low Engagement'
        WHEN m.program_points_earned < p.max_points * 0.75 THEN 'Moderate Engagement'
        ELSE 'High Engagement'
    END
ORDER BY avg_points_earned DESC
```

---

## Important Things to Know

### Why didn't a member earn points?

Use `json_event_history` to see what the system received, then compare to `json_earned_history`. If an event exists in event_history but NOT in earned_history (same `history_id`), the event was received but didn't qualify. Common reasons:

- Member already hit the max for that activity
- A prerequisite activity group hasn't been completed yet (see `locks` column)
- Duplicate within the cooldown period
- Activity happened outside the program date range
- Member was terminated

### What's the difference between incentives_timestamp and event_timestamp?

- **event_timestamp** = When the member actually did the activity
- **incentives_timestamp** = When our system processed it and awarded points

They're usually close, but can differ by hours or days.

### How does the balance add up?

```
current balance = total earned - total redeemed - total expired + manual adjustments
```

If the numbers don't match, look at `json_manual_adjustment_history` for admin corrections.

### What are "Reward Alternatives"?

Some programs award things other than points — like a $5 reduction on your specialist co-pay. These show up in `json_reward_alternative` with both the standard reward and the alternate reward name.

### What does "locks" mean?

In the event group file, the `locks` column means "this group is locked until another group is completed." For example, the Health Coaching group might be locked until the member completes their HSA Agreement.

---

## Date and ID Format Notes

- **Dates** are text in `YYYY-MM-DD HH:MI:SS` format. To do date math, cast them: `CAST(column AS DATE)`
- **IDs** (program_id, history_id, etc.) are text strings like `5c6da3e075e97168ade8e7c2`. Match them exactly.
- **member_id** is a number stored as text (like `1000352`).
- **reward** in earned_history is text. Cast it to a number for sums: `CAST(reward AS INT)`

---

## Full Column Reference

The tables below list every column in every file. Use this as a lookup when building queries.

### json_incentives_program_lu

| Column | Type | What It Is |
|--------|------|-----------|
| program_id | varchar | Unique ID for this program |
| collection_id | varchar | Collection this program belongs to |
| point_monetary_value | numeric | How much each point is worth in dollars (0 = marketplace) |
| currency | varchar | Currency (USD) |
| has_marketplace | varchar | Does this program have a shopping marketplace? (true/false) |
| rewards_provider | varchar | Who fulfills rewards — ADR (marketplace) or SHARECARE |
| reminder_period | varchar | How often members get reminders |
| start_date | varchar | When the program starts |
| end_date | varchar | When the program ends |
| blackout_date | varchar | Date earning is temporarily paused |
| program_rules_id | varchar | Internal rules reference |
| content | varchar | Program description text |
| expire_days_after_earned | int | Days before earned points expire |
| expire_days_after_program_end | int | Days after program ends before points expire |
| show_reward | varchar | Is the reward shown to members? (true/false) |
| max_points | int | Maximum points a member can earn total |
| expire_days_after_term | int | Days after termination before points expire |
| autoredeem | varchar | Do points auto-redeem? (true/false) |
| autoredeem_days_after_term | int | Days after termination to auto-redeem |
| autoredeem_min_points | int | Minimum balance needed for auto-redeem |
| program_name | varchar | Name members see |
| internal_name | varchar | Internal name for reference |
| last_updated_date | varchar | When this record was last changed |

### json_incentives_program_event_group_lu

| Column | Type | What It Is |
|--------|------|-----------|
| program_id | varchar | Which program this group belongs to |
| event_group_id | varchar | Unique ID for this group |
| event_group_name | varchar | Name of the activity group |
| locks | varchar | Which other group must be completed first (blank = no prerequisite) |
| repeatable | varchar | Can members earn from this group more than once? (true/false) |
| points | int | Points awarded at the group level (if applicable) |
| group_level_reward | varchar | Is the reward for completing the whole group? (true/false) |
| repeat_period | varchar | How often the group can be repeated |
| time_between_periods | varchar | Required gap between repeats |
| rewards_per_period | int | Max rewards per repeat window |
| reward_earned_after | int | How many activities must be done before reward fires |
| dynamic_start | varchar | Does the repeat window start from first activity? |
| max_repeats_per_day | int | Max earnings per day |
| last_updated_date | varchar | When this record was last changed |

### json_incentives_program_events_lu

| Column | Type | What It Is |
|--------|------|-----------|
| program_id | varchar | Which program |
| event_group_id | varchar | Which activity group this belongs to |
| event_id | varchar | Unique ID for this activity |
| event_type | varchar | What kind of trigger (assessment, tag change, etc.) |
| event_secondary_identifier | varchar | Matching key for incoming events |
| event_description | varchar | Activity name members see |
| start_date | varchar | When this activity starts being earnable |
| end_date | varchar | When this activity stops being earnable |
| blackout_date | varchar | Temporary pause date |
| look_back_period | timestamp | How far back to look for qualifying events |
| min_age | varchar | Minimum age to qualify |
| max_age | varchar | Maximum age to qualify |
| gender | varchar | Gender filter |
| conditions | varchar | Health condition filter |
| events_eligible | varchar | Eligibility filter |
| repeat_period | varchar | How often this can be re-earned |
| time_between_periods | varchar | Gap between re-earns |
| rewards_per_period | int | Max rewards per window |
| reward_earned_after | int | Activities needed before earning |
| dynamic_start | varchar | Window starts from first activity? |
| max_repeats_per_day | int | Max per day |
| points | int | Points this activity is worth |
| max_points | int | Max points earnable from this activity |
| group_level_reward | varchar | Part of a group reward? |
| reward_identifier | varchar | Reward type code |
| reward_name | varchar | Reward type name |
| tiered_reward_points | varchar | Tiered values (if applicable) |
| last_updated_date | varchar | When this record was last changed |

### json_programs

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | The member |
| member_program_id | varchar | This specific enrollment |
| program_id | varchar | Which program they're in |
| client_id | varchar | Client/sponsor ID |
| point_balance | int | Points they have right now |
| program_points_earned | int | All-time points earned |
| program_points_redeemed | int | All-time points spent |
| program_points_expired | int | All-time points expired |
| termination_aggressive | varchar | Aggressive termination applied? |
| termination_date | varchar | When they were removed (blank = still active) |
| collection_id | varchar | Program collection |
| employer_id | varchar | Their employer group |
| last_updated_date | varchar | When this record was last changed |

### json_ag_incentives

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | The member |
| incentives_activated | varchar | Are incentives turned on? (true/false) |

### json_earned_history

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | Who earned |
| history_id | varchar | Unique ID for this transaction |
| program_id | varchar | Which program |
| member_program_id | varchar | Which enrollment |
| client_id | varchar | Client ID |
| incentives_timestamp | varchar | When the system awarded it |
| event_timestamp | varchar | When the member actually did it |
| event_type | varchar | What kind of trigger |
| event_identifier | varchar | Matches to the activity config |
| event_description | varchar | Activity name |
| reward | varchar | Points awarded (cast to number for math) |
| point_balance | int | Balance after this transaction |
| manually_fired | varchar | Was this manually triggered? (true/false) |

### json_event_history

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | Who the event belongs to |
| history_id | varchar | Unique ID for this event |
| program_id | varchar | Which program |
| member_program_id | varchar | Which enrollment |
| client_id | varchar | Client ID |
| incentives_timestamp | varchar | When the system received it |
| event_timestamp | varchar | When it actually happened |
| event_type | varchar | What kind of trigger |
| event_identifier | varchar | Event matching key |
| event_description | varchar | Activity name |
| manually_fired | varchar | Manually triggered? (true/false) |

### json_redemption_history

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | Who redeemed |
| history_id | varchar | Unique ID for this redemption |
| program_id | varchar | Which program |
| member_program_id | varchar | Which enrollment |
| client_id | varchar | Client ID |
| incentives_timestamp | varchar | When the system processed it |
| event_timestamp | varchar | Event timestamp |
| redemption_date | varchar | When the redemption happened |
| points_redeemed | int | How many points were spent |
| points_word | varchar | Currency label (Dollars, Points) |
| point_balance | int | Balance after spending |
| transaction_id | varchar | External transaction reference |

### json_expiration_history

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | Whose points expired |
| history_id | varchar | Unique ID |
| program_id | varchar | Which program |
| member_program_id | varchar | Which enrollment |
| client_id | varchar | Client ID |
| incentives_timestamp | varchar | When the system processed it |
| event_timestamp | varchar | Event timestamp |
| expiration_date | varchar | When the points expired |
| points_expired | int | How many points expired |
| point_balance | int | Balance after expiration |

### json_manual_adjustment_history

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | Who was adjusted |
| history_id | varchar | Unique ID |
| program_id | varchar | Which program |
| member_program_id | varchar | Which enrollment |
| client_id | varchar | Client ID |
| incentives_timestamp | varchar | When the adjustment was made |
| event_timestamp | varchar | Event timestamp |
| points_adjusted | int | Points added (+) or removed (-) |
| description | varchar | Why the adjustment was made |
| point_balance | int | Balance after adjustment |

### json_reward_points

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | Who earned the reward |
| member_program_id | varchar | Which enrollment |
| member_reward_id | varchar | Unique reward instance (use to join to reward_alternative) |
| program_id | varchar | Which program |
| points | int | Points for this reward |
| points_word | varchar | Currency label (Dollars, Points) |
| earned_date | varchar | When it was earned |
| activity_date | varchar | When the activity happened |
| reward_reason | varchar | Why it was earned |
| event_id | varchar | Which activity triggered it |

### json_reward_alternative

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | Who earned |
| member_program_id | varchar | Which enrollment |
| member_reward_id | varchar | Reward instance (use to join to reward_points) |
| program_id | varchar | Which program |
| reward_name | varchar | Standard reward name |
| reward_identifier | varchar | Standard reward code |
| reward_alternate_name | varchar | Alternate reward (e.g., Specialist Copay $5 Reduction) |
| reward_alternate_identifier | varchar | Alternate reward code |
| earned_date | varchar | When earned |
| activity_date | varchar | When the activity happened |
| reward_reason | varchar | Why it was earned |
| event_id | varchar | Which activity triggered it |

### json_redemption_history_product

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | Who redeemed |
| history_id | varchar | Which redemption this belongs to (join to redemption_history) |
| program_id | varchar | Which program |
| product_name | varchar | What they got |
| points | varchar | Points spent on this item |
| total | numeric | Dollar value |
| quantity | varchar | How many |
| sku | varchar | Product SKU |
| reward_type | varchar | Category (eGift Card, Blue Rewards Card, etc.) |
| product_id | varchar | Product catalog ID |
