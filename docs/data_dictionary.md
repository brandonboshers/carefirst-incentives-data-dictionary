# Blue Rewards Incentive Data Guide

This guide explains the 13 data files you receive for Blue Rewards incentive reporting.

**New to this data? Start here:**
1. Read [What You're Getting](#what-youre-getting) to learn what each file is
2. Read [How They Fit Together](#how-they-fit-together) to see how files relate
3. Jump to [Report Queries](#report-queries) to run your first report

**Already familiar?**
- [Column Reference](column_reference.md) — Every column in every file
- [example_queries.sql](../sql/example_queries.sql) — 20 production-ready queries with detailed comments

---

## What You're Getting

You receive 13 files organized into four groups. Here's what each one is:

### Program Setup

These three files define your program — what activities are available and how many points each is worth. They don't contain member-level data.

| Short Name | Full File Name | What It Is |
|-----------|---------------|-----------|
| **Programs** | json_incentives_program_lu | Your incentive programs (name, date range, max points a member can earn) |
| **Activity Groups** | json_incentives_program_event_group_lu | Sections within a program that group related activities together |
| **Activities** | json_incentives_program_events_lu | The specific things a member can do to earn points |

**Example:** The program "Blue Rewards 2026" contains the activity group "Preventive Care," which contains the activity "Complete a Health Screening" worth 600 points.

### Member Enrollment

| Short Name | Full File Name | What It Is |
|-----------|---------------|-----------|
| **Members** | json_programs | Who is enrolled in which program, their current point balance, and lifetime totals |
| **Activation Flag** | json_ag_incentives | Whether incentives are turned on for a member (yes/no). Members with "false" won't earn. |

### Transaction History

These five files log every time something happens to a member's points. Each row is one transaction.

| Short Name | Full File Name | What It Is |
|-----------|---------------|-----------|
| **Earnings** | json_earned_history | Points awarded — the member completed an activity |
| **Events** | json_event_history | Activity signals received by the system, including ones that *didn't* earn (useful for troubleshooting) |
| **Redemptions** | json_redemption_history | Points spent by the member |
| **Expirations** | json_expiration_history | Points that expired because they weren't used in time |
| **Adjustments** | json_manual_adjustment_history | Points added or removed by an admin, with a reason |

### Reward Details

| Short Name | Full File Name | What It Is |
|-----------|---------------|-----------|
| **Products** | json_redemption_history_product | What the member actually bought with their points (gift card name, dollar amount, etc.) |
| **Rewards** | json_reward_points | Detailed record of each reward earned, with dates and the triggering activity |
| **Reward Alternatives** | json_reward_alternative | Non-point rewards like specialist co-pay reductions or premium discounts |

---

## How They Fit Together

Think of it like a restaurant menu:

- The **Program** is the restaurant
- **Activity Groups** are the menu sections (Appetizers, Entrees, Desserts)
- **Activities** are the individual items you can order

When a member "orders" (completes an activity), it creates an **Earning**. They accumulate points in their balance (**Members** file). Eventually they "cash out" by redeeming points for gift cards or other rewards (**Redemptions** + **Products**).

### How to Connect Any Two Files

Every file has a column called `program_id`. That's the universal key that links them all.

- To narrow to **one member**, filter on `member_id`
- To narrow to **one member in one specific program**, use `member_id` + `member_program_id`

See the [Connecting Files: Quick Reference](#connecting-files-quick-reference) table below for specific join paths.

---

## Key Things to Know

### How the Point Balance Works

**A member's current balance is simply: what they earned, minus what they spent, minus what expired, plus any admin adjustments.**

The formula using column names from the Members file:

> `point_balance` = `program_points_earned` − `program_points_redeemed` − `program_points_expired` + manual adjustments

If the math doesn't add up, look at the Adjustments file — it contains admin corrections not reflected in the other three totals.

### Two Types of Timestamps

**Every transaction has two dates — when the member did it, and when the system processed it.**

| Column | What It Means | Use It When... |
|--------|--------------|----------------|
| event_timestamp | When the member actually did the activity | You want "when did members do this?" |
| incentives_timestamp | When the system processed it and awarded points | You want "when were points given?" |

They're usually the same day, but can differ by hours or days due to processing lag.

### Why Would an Activity Not Earn Points?

**Not every activity results in points.** The Events file logs everything the system received. The Earnings file logs only what actually earned. If something is in Events but not in Earnings, one of these happened:

- Member already hit the maximum for that activity
- A prerequisite group wasn't completed yet (see below)
- Same activity repeated too quickly (within the cooldown window)
- Activity happened outside the program's date range
- Member was terminated from the program

### Prerequisites ("Locks")

**Some activity groups are locked until a prerequisite is completed.** In the Activity Groups file, the `locks` column names the prerequisite group. For example, "Health Coaching" might require "HSA Agreement" first. If `locks` is blank, there's no prerequisite — the member can earn immediately.

### Reward Alternatives

**Some programs offer non-point rewards in addition to (or instead of) points.** For example, a $5 reduction on specialist co-pays. These appear in the Reward Alternatives file. Connect them to the Rewards file using `member_reward_id` to see both the standard and alternate reward on one row.

### Filtering by Date

Most reports need a date range. Use `incentives_timestamp` for filtering in any of the history files. Example — to limit to 2026 only, add:

```sql
WHERE LEFT(eh.incentives_timestamp, 4) = '2026'
```

Or for a specific date range:

```sql
WHERE eh.incentives_timestamp >= '2026-01-01'
  AND eh.incentives_timestamp < '2027-01-01'
```

### Data Format Notes

| What | Format | Example | How to Use |
|------|--------|---------|-----------|
| Dates | Text | `2026-03-15 14:30:00` | Cast for date math: `CAST(column AS DATE)` |
| IDs | Text (hex) | `5c6da3e075e97168ade8e7c2` | Always match exactly as text |
| member_id | Numeric text | `1000352` | Can compare as text or cast to number |
| reward (points earned) | Text | `500` | Cast to number for sums: `CAST(reward AS INT)` |

---

## Connecting Files: Quick Reference

| I'm looking at... | I want to add... | Join to... | Match on... |
|-------------------|-----------------|-----------|-------------|
| Members | Program name/details | Programs | `program_id` |
| Earnings | Program name | Programs | `program_id` |
| Earnings | Activity config (group name, point value) | Activities | `program_id` + match `event_identifier` to `event_secondary_identifier` |
| Redemptions | What they bought | Products | `history_id` + `program_id` |
| Rewards | Alternate reward details | Reward Alternatives | `member_reward_id` |
| Events | Did it actually earn? | Earnings | `history_id` + `program_id` |
| Any history file | Member's current balance | Members | `member_id` + `member_program_id` |
| Programs (config) | Activity Groups in it | Activity Groups | `program_id` |
| Activity Groups | Activities in that group | Activities | `program_id` + `event_group_id` |

---

## Report Queries

These SQL queries are ready to copy into your database tool. Modify the date filters, column lists, or groupings to fit your needs. For 20 additional queries with detailed explanations, see [example_queries.sql](../sql/example_queries.sql).

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

### How many members are enrolled?

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

### Monthly engagement trend

```sql
SELECT
    LEFT(eh.incentives_timestamp, 7) AS month,
    COUNT(DISTINCT eh.member_id) AS active_earners,
    SUM(CAST(eh.reward AS INT)) AS total_points
FROM json_earned_history eh
GROUP BY LEFT(eh.incentives_timestamp, 7)
ORDER BY month
```

### How do employer groups compare?

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

### What are members spending points on?

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

### Member engagement segments

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

### Complete point history for one member

Add `WHERE member_id = '<id>'` to limit to one person.

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

### Monthly expirations

```sql
SELECT
    LEFT(ex.expiration_date, 7) AS month,
    COUNT(DISTINCT ex.member_id) AS members_affected,
    SUM(ex.points_expired) AS points_lost
FROM json_expiration_history ex
GROUP BY LEFT(ex.expiration_date, 7)
ORDER BY month
```

### Manual adjustment audit

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

### Which members have never earned anything?

```sql
SELECT
    m.member_id,
    m.employer_id,
    p.program_name,
    m.last_updated_date AS enrolled_since
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.program_points_earned = 0
  AND m.termination_date IS NULL
ORDER BY m.employer_id, m.member_id
```

### Top 50 earners

```sql
SELECT
    m.member_id,
    p.program_name,
    m.program_points_earned AS lifetime_earned,
    m.program_points_redeemed AS lifetime_redeemed,
    m.point_balance AS current_balance,
    p.max_points AS program_max
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.program_points_earned > 0
ORDER BY m.program_points_earned DESC
LIMIT 50
```

### Activity completion count per member

How many different activities has each member completed?

```sql
SELECT
    eh.member_id,
    p.program_name,
    COUNT(DISTINCT eh.event_description) AS unique_activities_completed,
    COUNT(*) AS total_earning_events,
    SUM(CAST(eh.reward AS INT)) AS total_points
FROM json_earned_history eh
JOIN json_incentives_program_lu p ON eh.program_id = p.program_id
GROUP BY eh.member_id, p.program_name
ORDER BY unique_activities_completed DESC
```

### Members who earned but never redeemed

```sql
SELECT
    m.member_id,
    p.program_name,
    m.program_points_earned,
    m.point_balance
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.program_points_earned > 0
  AND m.program_points_redeemed = 0
  AND m.termination_date IS NULL
ORDER BY m.point_balance DESC
```

### Earning activity by quarter

```sql
SELECT
    LEFT(eh.incentives_timestamp, 4) AS year,
    CASE
        WHEN CAST(SUBSTRING(eh.incentives_timestamp, 6, 2) AS INT) BETWEEN 1 AND 3 THEN 'Q1'
        WHEN CAST(SUBSTRING(eh.incentives_timestamp, 6, 2) AS INT) BETWEEN 4 AND 6 THEN 'Q2'
        WHEN CAST(SUBSTRING(eh.incentives_timestamp, 6, 2) AS INT) BETWEEN 7 AND 9 THEN 'Q3'
        ELSE 'Q4'
    END AS quarter,
    COUNT(DISTINCT eh.member_id) AS active_earners,
    SUM(CAST(eh.reward AS INT)) AS total_points,
    COUNT(*) AS earning_events
FROM json_earned_history eh
GROUP BY 1, 2
ORDER BY year, quarter
```

### Members who maxed out the program

```sql
SELECT
    m.member_id,
    p.program_name,
    m.program_points_earned,
    p.max_points,
    m.point_balance
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.program_points_earned >= p.max_points
  AND p.max_points > 0
ORDER BY p.program_name, m.member_id
```

### Average points per activity (which activities are worth the most?)

```sql
SELECT
    eh.event_description AS activity,
    COUNT(*) AS times_completed,
    AVG(CAST(eh.reward AS INT)) AS avg_points_per_completion,
    MIN(CAST(eh.reward AS INT)) AS min_points,
    MAX(CAST(eh.reward AS INT)) AS max_points
FROM json_earned_history eh
GROUP BY eh.event_description
ORDER BY avg_points_per_completion DESC
```

### Redemption frequency — how often do members redeem?

```sql
SELECT
    rh.member_id,
    p.program_name,
    COUNT(*) AS total_redemptions,
    SUM(rh.points_redeemed) AS total_points_spent,
    MIN(rh.redemption_date) AS first_redemption,
    MAX(rh.redemption_date) AS last_redemption
FROM json_redemption_history rh
JOIN json_incentives_program_lu p ON rh.program_id = p.program_id
GROUP BY rh.member_id, p.program_name
HAVING COUNT(*) > 1
ORDER BY total_redemptions DESC
```

### Year-over-year comparison

```sql
SELECT
    p.program_name,
    eh.event_description AS activity,
    COUNT(DISTINCT CASE WHEN LEFT(eh.incentives_timestamp,4) = '2025' THEN eh.member_id END) AS members_2025,
    SUM(CASE WHEN LEFT(eh.incentives_timestamp,4) = '2025' THEN CAST(eh.reward AS INT) ELSE 0 END) AS points_2025,
    COUNT(DISTINCT CASE WHEN LEFT(eh.incentives_timestamp,4) = '2026' THEN eh.member_id END) AS members_2026,
    SUM(CASE WHEN LEFT(eh.incentives_timestamp,4) = '2026' THEN CAST(eh.reward AS INT) ELSE 0 END) AS points_2026
FROM json_earned_history eh
JOIN json_incentives_program_lu p ON eh.program_id = p.program_id
WHERE LEFT(eh.incentives_timestamp,4) IN ('2025','2026')
GROUP BY p.program_name, eh.event_description
ORDER BY p.program_name, points_2026 DESC
```

### Program summary dashboard (one row per program with all key metrics)

```sql
SELECT
    p.program_name,
    p.start_date,
    p.end_date,
    p.max_points,
    COUNT(DISTINCT m.member_id) AS total_members,
    COUNT(DISTINCT CASE WHEN m.termination_date IS NULL THEN m.member_id END) AS active_members,
    COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) AS members_who_earned,
    SUM(m.program_points_earned) AS total_points_earned,
    SUM(m.program_points_redeemed) AS total_points_redeemed,
    SUM(m.program_points_expired) AS total_points_expired,
    SUM(m.point_balance) AS total_unredeemed_balance,
    ROUND(
        COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) * 100.0
        / NULLIF(COUNT(DISTINCT m.member_id), 0), 1
    ) AS earning_rate_pct
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
GROUP BY p.program_name, p.start_date, p.end_date, p.max_points
ORDER BY total_members DESC
```

---

## Questions?

Contact your Sharecare Client Reporting team representative.

**Additional resources:**
- [Column Reference](column_reference.md) — Every column in every file with descriptions
- [example_queries.sql](../sql/example_queries.sql) — 20 queries with extensive inline comments
