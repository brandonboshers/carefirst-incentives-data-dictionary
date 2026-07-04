# Blue Rewards Incentive Data Guide

This guide explains the 13 data files you receive for Blue Rewards incentive reporting. It's written so you can understand the data without needing to read SQL first.

For SQL examples, skip to [Report Queries](#report-queries) at the bottom, or open the dedicated **[example_queries.sql](../sql/example_queries.sql)** file (20 queries with full comments).

For a column-by-column reference, see **[column_reference.md](column_reference.md)**.

---

## What You're Getting

You receive 13 files. Each file is a table of data. Together, they tell you everything about your incentive program: what's configured, who's enrolled, what members earned, what they spent, and what expired.

We'll refer to them by short names throughout this guide:

| Short Name | Full File Name | What It Is |
|-----------|---------------|-----------|
| **Programs** | json_incentives_program_lu | Your incentive programs — names, dates, point limits |
| **Activity Groups** | json_incentives_program_event_group_lu | Groupings of related activities (e.g., "Preventive Screening", "Coaching") |
| **Activities** | json_incentives_program_events_lu | Each specific activity a member can do to earn points |
| **Members** | json_programs | Who is enrolled, their balance, and lifetime totals |
| **Activation Flag** | json_ag_incentives | Simple yes/no: are incentives turned on for this member? |
| **Earnings** | json_earned_history | Every time points were awarded to a member |
| **Events** | json_event_history | Every activity signal received (even if it didn't result in points) |
| **Redemptions** | json_redemption_history | Every time a member spent points |
| **Products** | json_redemption_history_product | What they bought when they redeemed (gift cards, etc.) |
| **Expirations** | json_expiration_history | Points that expired |
| **Adjustments** | json_manual_adjustment_history | Manual corrections made by an administrator |
| **Rewards** | json_reward_points | Detailed reward records with dates and triggering activity |
| **Reward Alternatives** | json_reward_alternative | Non-point rewards (co-pay reductions, premium discounts) |

---

## How They Fit Together

The files form a simple hierarchy:

**A Program contains Activity Groups, which contain Activities.**

Think of your Blue Rewards program like a menu. The menu (Programs) has sections (Activity Groups) like "Preventive Care" or "Wellness." Each section has items (Activities) like "Complete a Health Screening" worth 500 points.

**Members enroll in a Program.** Once enrolled, they complete Activities, which creates Earnings. They can then spend those points (Redemptions) on gift cards or other products (Products). Points they don't spend may eventually Expire.

**The one field that connects everything is `program_id`.** Every file has it. That's how you join any two files together.

To narrow down to one person, add `member_id`. To narrow to one person in one specific program, use both `member_id` and `member_program_id`.

---

## Understanding the Key Files

### Members (json_programs) — Your Starting Point

This is usually where you'll start. Each row is one member enrolled in one program. Key columns:

- **point_balance** — What they have right now
- **program_points_earned** — Everything they've ever earned
- **program_points_redeemed** — Everything they've ever spent
- **program_points_expired** — Everything that expired
- **termination_date** — If blank, they're still active. If filled, they've been removed.
- **employer_id** — Their employer group (useful for breaking out reports)

**How the balance works:**
```
Current Balance = Earned − Redeemed − Expired + Adjustments
```

### Earnings (json_earned_history) — What Members Did

Each row is one time a member earned points. Key columns:

- **event_description** — The activity name (e.g., "Complete a Preventive Screening")
- **reward** — How many points they got (note: stored as text, cast to number for math)
- **event_timestamp** — When the member did the activity
- **incentives_timestamp** — When the system awarded the points (may be slightly later)

### Events (json_event_history) — Including Things That Didn't Earn

Similar to Earnings, but includes activities that were received by the system but **did not** result in points. Why would something not earn?

- Member already maxed out that activity
- A prerequisite wasn't completed yet (see "Gating" below)
- It was a duplicate within the cooldown window
- The activity happened outside the program's date range
- The member was terminated

**How to find what didn't earn:** Compare Events to Earnings using `history_id`. If an event's `history_id` has no match in Earnings, it didn't result in points.

### Redemptions + Products — What They Spent On

**Redemptions** shows each time a member spent points. **Products** shows what they actually got (e.g., a $25 Amazon gift card). Connect them using `history_id` + `program_id`. One redemption can have multiple products.

### Expirations — Points Lost to Time

Each row is points that expired because the member didn't use them within the allowed window. The `expiration_date` tells you when, and `points_expired` tells you how many.

### Adjustments — Manual Corrections

Admin corrections — points added or removed manually. The `description` column explains why (e.g., "Refund - IRS3227" or "Manual points for RealAge re-take activity"). Use this to reconcile balances that don't add up from Earnings/Redemptions/Expirations alone.

---

## Gating (Prerequisites)

Some activity groups are locked until a member completes a different group first. For example:

> "Health Coaching" rewards are **locked** until the member completes "HSA Agreement"

You'll see this in the Activity Groups file — the `locks` column names the prerequisite group. If it's blank, there's no prerequisite.

---

## Connecting Files Together

Here's a plain-English guide to which files you join and what field you use:

| I'm looking at... | I want to add... | Join to... | Match on... |
|-------------------|-----------------|-----------|-------------|
| Members | The program name | Programs | `program_id` |
| Earnings | The program name | Programs | `program_id` |
| Earnings | Activity details (points config, group) | Activities | `program_id` and `event_identifier` = `event_secondary_identifier` |
| Redemptions | What they bought | Products | `history_id` and `program_id` |
| Rewards | Alternate reward info | Reward Alternatives | `member_reward_id` |
| Events | Whether it earned or not | Earnings | `history_id` and `program_id` |
| Any history file | Member's current balance | Members | `member_id` and `member_program_id` |
| Activity Groups | The individual activities | Activities | `program_id` and `event_group_id` |
| Programs | Their activity groups | Activity Groups | `program_id` |

---

## Report Queries

Below are SQL queries ready to copy into your database tool. Each one answers a common reporting question.

### What activities are available and how many points are they worth?

```sql
SELECT
    p.program_name,
    eg.event_group_name     AS activity_group,
    eg.locks                AS prerequisite,
    e.event_description     AS activity,
    e.points
FROM json_incentives_program_lu p
JOIN json_incentives_program_event_group_lu eg
    ON p.program_id = eg.program_id
JOIN json_incentives_program_events_lu e
    ON eg.program_id = e.program_id
    AND eg.event_group_id = e.event_group_id
ORDER BY p.program_name, eg.event_group_name, e.event_description
```

### How many members are enrolled and what are their balances?

```sql
SELECT
    p.program_name,
    COUNT(DISTINCT m.member_id) AS total_enrolled,
    COUNT(DISTINCT CASE WHEN m.termination_date IS NULL THEN m.member_id END) AS active,
    COUNT(DISTINCT CASE WHEN m.termination_date IS NOT NULL THEN m.member_id END) AS terminated,
    SUM(m.program_points_earned) AS total_points_earned,
    SUM(m.point_balance) AS total_unredeemed,
    AVG(m.point_balance) AS avg_balance
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
GROUP BY p.program_name
ORDER BY total_enrolled DESC
```

### Which activities are most popular?

```sql
SELECT
    eh.event_description AS activity,
    COUNT(DISTINCT eh.member_id) AS unique_members,
    COUNT(*) AS times_completed,
    SUM(CAST(eh.reward AS INT)) AS total_points
FROM json_earned_history eh
GROUP BY eh.event_description
ORDER BY unique_members DESC
```

### Are members staying engaged over time? (Monthly trend)

```sql
SELECT
    LEFT(eh.incentives_timestamp, 7) AS month,
    COUNT(DISTINCT eh.member_id) AS active_earners,
    SUM(CAST(eh.reward AS INT)) AS total_points
FROM json_earned_history eh
GROUP BY LEFT(eh.incentives_timestamp, 7)
ORDER BY month
```

### How do different employer groups compare?

```sql
SELECT
    m.employer_id,
    COUNT(DISTINCT m.member_id) AS enrolled,
    COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) AS earned_something,
    ROUND(
        COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) * 100.0
        / NULLIF(COUNT(DISTINCT m.member_id), 0), 1
    ) AS earning_rate_pct
FROM json_programs m
WHERE m.termination_date IS NULL
GROUP BY m.employer_id
ORDER BY enrolled DESC
```

### What are members redeeming for?

```sql
SELECT
    rp.product_name,
    rp.reward_type,
    COUNT(DISTINCT rh.member_id) AS redeemers,
    SUM(rh.points_redeemed) AS points_spent,
    SUM(rp.total) AS dollar_value
FROM json_redemption_history rh
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id
    AND rh.program_id = rp.program_id
GROUP BY rp.product_name, rp.reward_type
ORDER BY points_spent DESC
```

### How many points are unredeemed? (Financial liability)

```sql
SELECT
    p.program_name,
    COUNT(DISTINCT m.member_id) AS members_with_balance,
    SUM(m.point_balance) AS unredeemed_points,
    SUM(m.point_balance) * p.point_monetary_value AS estimated_dollar_value
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.point_balance > 0 AND m.termination_date IS NULL
GROUP BY p.program_name, p.point_monetary_value
ORDER BY unredeemed_points DESC
```

### How engaged are members? (Segmentation)

```sql
SELECT
    CASE
        WHEN m.program_points_earned = 0 THEN '1 - Never Earned'
        WHEN m.program_points_earned < p.max_points * 0.25 THEN '2 - Low'
        WHEN m.program_points_earned < p.max_points * 0.75 THEN '3 - Moderate'
        ELSE '4 - High'
    END AS engagement_tier,
    COUNT(*) AS members,
    AVG(m.program_points_earned) AS avg_points,
    AVG(m.point_balance) AS avg_balance
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.termination_date IS NULL AND p.max_points > 0
GROUP BY
    CASE
        WHEN m.program_points_earned = 0 THEN '1 - Never Earned'
        WHEN m.program_points_earned < p.max_points * 0.25 THEN '2 - Low'
        WHEN m.program_points_earned < p.max_points * 0.75 THEN '3 - Moderate'
        ELSE '4 - High'
    END
ORDER BY engagement_tier
```

### Complete point history for a member

```sql
SELECT member_id, incentives_timestamp,
       'Earned' AS transaction, CAST(reward AS INT) AS points, event_description AS details
FROM json_earned_history
UNION ALL
SELECT member_id, incentives_timestamp,
       'Redeemed', -1 * points_redeemed, 'Marketplace Redemption'
FROM json_redemption_history
UNION ALL
SELECT member_id, incentives_timestamp,
       'Expired', -1 * points_expired, 'Points Expired'
FROM json_expiration_history
UNION ALL
SELECT member_id, incentives_timestamp,
       'Adjustment', points_adjusted, description
FROM json_manual_adjustment_history
ORDER BY member_id, incentives_timestamp
```

### How many points are expiring? (Monthly)

```sql
SELECT
    LEFT(ex.expiration_date, 7) AS month,
    COUNT(DISTINCT ex.member_id) AS members_affected,
    SUM(ex.points_expired) AS points_lost
FROM json_expiration_history ex
GROUP BY LEFT(ex.expiration_date, 7)
ORDER BY month
```

### What manual adjustments have been made?

```sql
SELECT
    ma.description AS reason,
    COUNT(*) AS times,
    COUNT(DISTINCT ma.member_id) AS members,
    SUM(ma.points_adjusted) AS net_points
FROM json_manual_adjustment_history ma
GROUP BY ma.description
ORDER BY ABS(SUM(ma.points_adjusted)) DESC
```

---

## Questions?

Contact your Sharecare Client Reporting team representative. For the full column-by-column field listing, see [column_reference.md](column_reference.md).
