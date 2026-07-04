# Blue Rewards Incentive Data Guide

> **Start here.** This document explains the 13 JSON data files you receive, how they fit together, and how to use them for reporting.
>
> **Additional resources:**
> - [Column Reference](column_reference.md) — Every column in every file, with descriptions
> - [Example Queries (SQL)](../sql/example_queries.sql) — 20 ready-to-run queries with detailed comments

---

## Table of Contents

1. [Your 13 Files](#your-13-files)
2. [How They Fit Together](#how-they-fit-together)
3. [Important Concepts](#important-concepts)
4. [How to Connect the Files](#how-to-connect-the-files)
5. [Report Examples](#report-examples)

---

## Your 13 Files

You receive four categories of data:

### Program Setup (3 files)

These define your program — what activities exist and how many points each is worth. They don't contain any member-level data.

| File | One Row = | Purpose |
|------|-----------|---------|
| **json_incentives_program_lu** | One incentive program | The master list of your programs with names, dates, and max points |
| **json_incentives_program_event_group_lu** | One group of activities | Groups related activities together (e.g., "Health Screening", "Coaching") |
| **json_incentives_program_events_lu** | One earnable activity | The specific things members can do to earn (e.g., "Complete RealAge Test") |

### Member Enrollment (2 files)

| File | One Row = | Purpose |
|------|-----------|---------|
| **json_programs** | One member in one program | Shows who is enrolled, their current balance, and lifetime totals |
| **json_ag_incentives** | One member | Simple yes/no: are incentives turned on for this person? |

### Transaction History (5 files)

These are the activity logs — one row every time something happens to a member's points.

| File | One Row = | Purpose |
|------|-----------|---------|
| **json_earned_history** | One earning event | Member completed an activity and received points |
| **json_event_history** | One raw event | System received an activity signal (may or may not have earned) |
| **json_redemption_history** | One redemption | Member spent their points |
| **json_expiration_history** | One expiration | Points expired due to time limits |
| **json_manual_adjustment_history** | One admin correction | Points manually added or removed with a reason |

### Reward Details (3 files)

| File | One Row = | Purpose |
|------|-----------|---------|
| **json_reward_points** | One reward earned | Detailed reward record with dates and the triggering activity |
| **json_reward_alternative** | One alternate reward | Non-point rewards (e.g., co-pay reductions, premium discounts) |
| **json_redemption_history_product** | One product in a redemption | What the member actually bought (product name, gift card type, dollar amount) |

---

## How They Fit Together

### The Big Picture

```
Programs contain → Activity Groups contain → Activities

Members enroll in → Programs

Members complete → Activities → which creates → Earning History

Members spend points → which creates → Redemption History → with → Product Details

Points can also → Expire or be Manually Adjusted
```

### The Three Keys You Need

| When you want to... | Connect files using... |
|---------------------|----------------------|
| Link anything to a specific **program** | `program_id` (every file has this) |
| Link anything to a specific **member** | `member_id` |
| Link to a member's **enrollment in one program** | `member_id` + `member_program_id` |

### Quick Join Reference

| I have this file... | I want to add... | Join to... | Using... |
|--------------------|-----------------|-----------|---------|
| json_programs | Program name and details | json_incentives_program_lu | `program_id` |
| json_earned_history | Program name | json_incentives_program_lu | `program_id` |
| json_earned_history | Activity config details | json_incentives_program_events_lu | `program_id` + `event_identifier = event_secondary_identifier` |
| json_redemption_history | What they bought | json_redemption_history_product | `history_id` + `program_id` |
| json_reward_points | Alternate reward info | json_reward_alternative | `member_reward_id` |
| json_event_history | Did it earn? | json_earned_history | `history_id` + `program_id` |
| Any history file | Member's current balance | json_programs | `member_id` + `member_program_id` |

---

## Important Concepts

### How the Balance Works

A member's `point_balance` in json_programs should equal:

```
Points Earned − Points Redeemed − Points Expired + Manual Adjustments = Current Balance
```

If numbers don't match, check `json_manual_adjustment_history` for admin corrections.

### Events vs. Earnings: What's the Difference?

- **json_event_history** = "The system received a signal that a member did something"
- **json_earned_history** = "Points were actually awarded"

Not every event results in an earning. An event can fail to earn if:
- The member already hit the maximum for that activity
- A prerequisite group hasn't been completed yet (gating)
- It's a duplicate within the cooldown period
- The activity happened outside the program's date range
- The member was terminated

**To find events that didn't earn:** Look for `history_id` values in event_history that have no match in earned_history.

### Gating (Locks)

Some activity groups require a prerequisite. The `locks` column in the event group file tells you which group must be completed first. Example: "Health Coaching" might be locked until "HSA Agreement" is completed.

### Two Timestamps

- **event_timestamp** = When the member did the activity
- **incentives_timestamp** = When the system processed it and awarded points

Use event_timestamp for "when did activity happen" reports. Use incentives_timestamp for "when were points given" reports.

### Reward Alternatives

Some programs offer non-point rewards (like a $5 specialist co-pay reduction). These appear in `json_reward_alternative`. Join it to `json_reward_points` using `member_reward_id`.

### Data Format Notes

- **Dates** are text formatted as `2026-03-15 14:30:00`. Cast to DATE for math: `CAST(column AS DATE)`
- **IDs** are text strings like `5c6da3e075e97168ade8e7c2`. Always match exactly.
- **member_id** is a number stored as text (e.g., `1000352`).
- **reward** in earned_history is text. Cast to number for sums: `CAST(reward AS INT)`

---

## How to Connect the Files

### See all activities available in a program

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

### See each member's balance with program name

```sql
SELECT
    m.member_id,
    p.program_name,
    m.employer_id,
    m.point_balance          AS current_balance,
    m.program_points_earned  AS lifetime_earned,
    m.program_points_redeemed AS lifetime_spent,
    m.termination_date
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
ORDER BY p.program_name, m.member_id
```

### See what each member earned

```sql
SELECT
    eh.member_id,
    p.program_name,
    eh.event_description     AS activity,
    CAST(eh.reward AS INT)   AS points,
    eh.event_timestamp       AS activity_date,
    eh.incentives_timestamp  AS awarded_date
FROM json_earned_history eh
JOIN json_incentives_program_lu p ON eh.program_id = p.program_id
ORDER BY eh.member_id, eh.event_timestamp
```

### See what members redeemed for

```sql
SELECT
    rh.member_id,
    rh.redemption_date,
    rh.points_redeemed,
    rp.product_name,
    rp.reward_type,
    rp.total AS dollar_value
FROM json_redemption_history rh
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id
    AND rh.program_id = rp.program_id
ORDER BY rh.redemption_date DESC
```

### Build a complete point history for any member

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

### Find events that didn't earn

```sql
SELECT
    ev.member_id,
    ev.event_description,
    ev.event_timestamp
FROM json_event_history ev
LEFT JOIN json_earned_history eh
    ON ev.history_id = eh.history_id
    AND ev.program_id = eh.program_id
WHERE eh.history_id IS NULL
```

---

## Report Examples

### Program enrollment summary

```sql
SELECT
    p.program_name,
    COUNT(DISTINCT m.member_id) AS total_enrolled,
    COUNT(DISTINCT CASE WHEN m.termination_date IS NULL THEN m.member_id END) AS active,
    COUNT(DISTINCT CASE WHEN m.termination_date IS NOT NULL THEN m.member_id END) AS terminated,
    SUM(m.program_points_earned) AS total_points_earned,
    AVG(m.point_balance) AS avg_balance
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
GROUP BY p.program_name
ORDER BY total_enrolled DESC
```

### Most popular activities

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

### Earning rate by employer group

```sql
SELECT
    m.employer_id,
    COUNT(DISTINCT m.member_id) AS enrolled,
    COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) AS earners,
    ROUND(
        COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) * 100.0
        / NULLIF(COUNT(DISTINCT m.member_id), 0), 1
    ) AS earning_rate_pct
FROM json_programs m
WHERE m.termination_date IS NULL
GROUP BY m.employer_id
ORDER BY enrolled DESC
```

### Points liability (unredeemed balance)

```sql
SELECT
    p.program_name,
    COUNT(DISTINCT m.member_id) AS members_with_balance,
    SUM(m.point_balance) AS unredeemed_points,
    SUM(m.point_balance) * p.point_monetary_value AS dollar_value
FROM json_programs m
JOIN json_incentives_program_lu p ON m.program_id = p.program_id
WHERE m.point_balance > 0 AND m.termination_date IS NULL
GROUP BY p.program_name, p.point_monetary_value
ORDER BY unredeemed_points DESC
```

### Most popular redemption products

```sql
SELECT
    rp.product_name,
    rp.reward_type,
    COUNT(DISTINCT rh.member_id) AS redeemers,
    SUM(rh.points_redeemed) AS points_spent,
    SUM(rp.total) AS dollar_value
FROM json_redemption_history rh
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id AND rh.program_id = rp.program_id
GROUP BY rp.product_name, rp.reward_type
ORDER BY points_spent DESC
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

### Expirations by month

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

---

## Next Steps

- **Full column reference** — See [column_reference.md](column_reference.md) for every field in every file
- **20 detailed queries** — See [sql/example_queries.sql](../sql/example_queries.sql) for production-ready SQL with extensive comments
- **Questions?** — Contact your Sharecare Client Reporting team representative
