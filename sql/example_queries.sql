-- ============================================================================
-- CareFirst Incentives JSON Data - Example Queries
-- ============================================================================
--
-- PURPOSE:
--   This file contains ready-to-use SQL examples for reporting on the 13
--   incentive JSON data files delivered by Sharecare. Each query includes
--   detailed comments explaining the logic, join relationships, and how to
--   adapt it for your reporting needs.
--
-- FILES REFERENCED:
--   Configuration (lookup/reference - no member data):
--     1. json_incentives_program_lu          - Program definitions
--     2. json_incentives_program_event_group_lu - Event group definitions
--     3. json_incentives_program_events_lu   - Individual event definitions
--
--   Member Enrollment:
--     4. json_programs                       - Member program enrollments
--     5. json_ag_incentives                  - Member activation flag
--
--   Transaction History:
--     6. json_earned_history                 - Points awarded
--     7. json_event_history                  - Raw events (may not earn)
--     8. json_redemption_history             - Points redeemed
--     9. json_expiration_history             - Points expired
--    10. json_manual_adjustment_history      - Admin adjustments
--
--   Reward Details:
--    11. json_reward_points                  - Reward earning details
--    12. json_reward_alternative             - Non-standard rewards
--    13. json_redemption_history_product     - Marketplace product details
--
-- JOIN KEY SUMMARY:
--   program_id         - Links ALL files together (the program)
--   member_id          - Identifies the member across all member-level files
--   member_program_id  - Specific enrollment of a member in a program
--   event_group_id     - Links events to their parent group
--   history_id         - Unique transaction; links redemption to product detail
--   member_reward_id   - Links reward_points to reward_alternative
--   event_id           - Links reward_points/reward_alternative to events_lu
--
-- DATA TYPE NOTES:
--   - All date columns are VARCHAR in 'YYYY-MM-DD HH:MI:SS' format.
--     Cast to DATE or TIMESTAMP for date arithmetic.
--   - All ID columns (program_id, history_id, etc.) are VARCHAR hex strings.
--   - member_id is a numeric string.
--   - The "reward" column in json_earned_history is VARCHAR; cast to INT for sums.
--
-- ============================================================================


-- ============================================================================
-- QUERY 1: PROGRAM CATALOG
-- ============================================================================
-- What it does:
--   Lists all incentive programs with their full event structure.
--   This is your "menu" of what members can earn and how the program is
--   organized into event groups and individual activities.
--
-- Use this to:
--   - Understand what activities are available in each program
--   - See point values for each activity
--   - Identify gating requirements (locks)
--   - Confirm program date ranges
-- ============================================================================

SELECT
    p.program_id,
    p.program_name,
    p.internal_name,
    p.start_date                        AS program_start,
    p.end_date                          AS program_end,
    p.max_points                        AS program_max_points,
    p.point_monetary_value,
    p.rewards_provider,

    -- Event Group level
    eg.event_group_id,
    eg.event_group_name,
    eg.locks                            AS prerequisite_group,
    eg.repeatable                       AS group_repeatable,
    eg.points                           AS group_level_points,

    -- Individual Event level
    e.event_id,
    e.event_description                 AS activity_name,
    e.event_type                        AS trigger_type,
    e.points                            AS event_points,
    e.max_points                        AS event_max_points,
    e.reward_name,
    e.start_date                        AS event_start,
    e.end_date                          AS event_end

FROM json_incentives_program_lu p

-- Join to event groups: one program has many event groups
JOIN json_incentives_program_event_group_lu eg
    ON p.program_id = eg.program_id

-- Join to events: one event group has many individual events
JOIN json_incentives_program_events_lu e
    ON eg.program_id = e.program_id
    AND eg.event_group_id = e.event_group_id

ORDER BY
    p.program_name,
    eg.event_group_name,
    e.event_description;


-- ============================================================================
-- QUERY 2: MEMBER ENROLLMENT SUMMARY
-- ============================================================================
-- What it does:
--   Shows each member's enrollment in incentive programs along with their
--   current point balance and lifetime totals.
--
-- Use this to:
--   - Count how many members are enrolled per program
--   - See current balances and lifetime earning/redemption totals
--   - Identify terminated members
--   - Reconcile point balances
--
-- Balance formula:
--   point_balance = program_points_earned
--                 - program_points_redeemed
--                 - program_points_expired
--                 + net(manual_adjustments)
-- ============================================================================

SELECT
    m.member_id,
    m.member_program_id,
    p.program_name,
    p.internal_name,
    m.employer_id,
    m.point_balance                     AS current_balance,
    m.program_points_earned             AS lifetime_earned,
    m.program_points_redeemed           AS lifetime_redeemed,
    m.program_points_expired            AS lifetime_expired,
    m.termination_date,

    -- Calculated check: does balance reconcile?
    (m.program_points_earned
     - m.program_points_redeemed
     - m.program_points_expired)        AS calculated_balance

FROM json_programs m

-- Join to program lookup for readable names
JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id

ORDER BY
    p.program_name,
    m.member_id;


-- ============================================================================
-- QUERY 3: POINTS EARNED BY ACTIVITY
-- ============================================================================
-- What it does:
--   Aggregates all earning transactions by program and activity (event).
--   Shows how many times each activity was completed, by how many unique
--   members, and the total points awarded.
--
-- Use this to:
--   - Understand which activities drive the most engagement
--   - Compare participation across different program events
--   - Identify underutilized activities
-- ============================================================================

SELECT
    p.program_name,
    eh.event_description                AS activity_name,
    COUNT(*)                            AS times_earned,
    COUNT(DISTINCT eh.member_id)        AS unique_members,
    SUM(CAST(eh.reward AS INT))         AS total_points_awarded

FROM json_earned_history eh

-- Join to program lookup for the program name
JOIN json_incentives_program_lu p
    ON eh.program_id = p.program_id

GROUP BY
    p.program_name,
    eh.event_description

ORDER BY
    p.program_name,
    total_points_awarded DESC;


-- ============================================================================
-- QUERY 4: MONTHLY EARNING TREND
-- ============================================================================
-- What it does:
--   Shows earning activity over time by month. Tracks the number of earning
--   events, unique earners, and total points per month.
--
-- Use this to:
--   - Monitor program engagement trends over time
--   - Identify seasonal patterns
--   - Spot drops or spikes in activity
--
-- NOTE: incentives_timestamp is when the system processed the earning.
--       event_timestamp is when the qualifying activity actually occurred.
--       Use incentives_timestamp for "when was the reward given" reporting.
--       Use event_timestamp for "when did the member do the activity" reporting.
-- ============================================================================

SELECT
    LEFT(eh.incentives_timestamp, 7)    AS year_month,
    COUNT(*)                            AS earning_events,
    COUNT(DISTINCT eh.member_id)        AS active_earners,
    SUM(CAST(eh.reward AS INT))         AS total_points_awarded

FROM json_earned_history eh

GROUP BY
    LEFT(eh.incentives_timestamp, 7)

ORDER BY
    year_month;


-- ============================================================================
-- QUERY 5: REDEMPTION SUMMARY BY PRODUCT
-- ============================================================================
-- What it does:
--   Shows what members are redeeming their points for in the marketplace.
--   Joins redemption transactions to their product line-item details.
--
-- Use this to:
--   - See which products/gift cards are most popular
--   - Track total dollar value of redemptions
--   - Understand member reward preferences
--
-- JOIN LOGIC:
--   json_redemption_history (one row per redemption transaction)
--   -> json_redemption_history_product (one row per product in that redemption)
--   Joined on history_id + program_id
-- ============================================================================

SELECT
    rp.product_name,
    rp.reward_type,
    COUNT(*)                            AS redemption_line_items,
    COUNT(DISTINCT rh.member_id)        AS unique_redeemers,
    SUM(rh.points_redeemed)             AS total_points_redeemed,
    SUM(rp.total)                       AS total_dollar_value

FROM json_redemption_history rh

-- Join to product details: one redemption can have multiple products
JOIN json_redemption_history_product rp
    ON rh.history_id = rp.history_id
    AND rh.program_id = rp.program_id

GROUP BY
    rp.product_name,
    rp.reward_type

ORDER BY
    total_points_redeemed DESC;


-- ============================================================================
-- QUERY 6: FULL POINT LIFECYCLE (AUDIT TRAIL)
-- ============================================================================
-- What it does:
--   Unions ALL point-changing transactions into a single timeline per member.
--   This gives you a complete ledger showing every earn, redemption,
--   expiration, and manual adjustment in chronological order.
--
-- Use this to:
--   - Audit a specific member's point history
--   - Reconcile balances
--   - Trace the source of discrepancies
--
-- TRANSACTION TYPES:
--   EARNED     = Points added from completing an activity
--   REDEEMED   = Points spent in the marketplace (shown as negative)
--   EXPIRED    = Points lost due to time limits (shown as negative)
--   ADJUSTMENT = Admin correction (positive = add, negative = remove)
-- ============================================================================

SELECT
    member_id,
    member_program_id,
    program_id,
    incentives_timestamp,
    transaction_type,
    points_change,
    description
FROM (

    -- EARNINGS: points awarded for completing activities
    SELECT
        member_id,
        member_program_id,
        program_id,
        incentives_timestamp,
        'EARNED'                        AS transaction_type,
        CAST(reward AS INT)             AS points_change,
        event_description               AS description
    FROM json_earned_history

    UNION ALL

    -- REDEMPTIONS: points spent (negative)
    SELECT
        member_id,
        member_program_id,
        program_id,
        incentives_timestamp,
        'REDEEMED'                      AS transaction_type,
        -1 * points_redeemed            AS points_change,
        'Marketplace Redemption'        AS description
    FROM json_redemption_history

    UNION ALL

    -- EXPIRATIONS: points lost to time limits (negative)
    SELECT
        member_id,
        member_program_id,
        program_id,
        incentives_timestamp,
        'EXPIRED'                       AS transaction_type,
        -1 * points_expired             AS points_change,
        'Points Expired'                AS description
    FROM json_expiration_history

    UNION ALL

    -- MANUAL ADJUSTMENTS: admin corrections (positive or negative)
    SELECT
        member_id,
        member_program_id,
        program_id,
        incentives_timestamp,
        'ADJUSTMENT'                    AS transaction_type,
        points_adjusted                 AS points_change,
        description                     AS description
    FROM json_manual_adjustment_history

) all_transactions

ORDER BY
    member_id,
    member_program_id,
    incentives_timestamp;


-- ============================================================================
-- QUERY 7: EVENTS THAT DID NOT RESULT IN POINTS
-- ============================================================================
-- What it does:
--   Compares raw events (json_event_history) to earned events
--   (json_earned_history) to find activity that was received by the system
--   but did NOT result in a point award.
--
-- Use this to:
--   - Understand why certain activities didn't earn
--   - Identify members who hit caps or were blocked by gating
--   - Troubleshoot "why didn't I get my points?" questions
--
-- COMMON REASONS an event doesn't earn:
--   1. Member already reached max_points for that event
--   2. Event group is locked (prerequisite not yet completed)
--   3. Duplicate within the repeat_period window
--   4. Event occurred outside the program date range
--   5. Member was terminated from the program
-- ============================================================================

SELECT
    ev.member_id,
    ev.program_id,
    ev.event_description,
    ev.event_timestamp,
    ev.event_type,
    ev.event_identifier

FROM json_event_history ev

-- LEFT JOIN to earned: if no match, the event did NOT result in points
LEFT JOIN json_earned_history eh
    ON ev.history_id = eh.history_id
    AND ev.program_id = eh.program_id

-- Keep only the events with NO corresponding earned record
WHERE eh.history_id IS NULL

ORDER BY
    ev.member_id,
    ev.event_timestamp;


-- ============================================================================
-- QUERY 8: REWARD DETAILS WITH ALTERNATIVES
-- ============================================================================
-- What it does:
--   Shows the full reward picture per member, including both standard point
--   rewards and alternative rewards (like co-pay reductions or premium
--   discounts) that a member may have earned.
--
-- Use this to:
--   - Report on non-monetary rewards (co-pay reductions, etc.)
--   - See which reward alternatives members are earning
--   - Link rewards back to the specific activity that triggered them
--
-- JOIN LOGIC:
--   json_reward_points and json_reward_alternative share the same grain:
--   member_id + member_program_id + member_reward_id.
--   LEFT JOIN reward_alternative to reward_points to see both on one row.
-- ============================================================================

SELECT
    rp.member_id,
    rp.program_id,
    rp.member_reward_id,
    rp.points,
    rp.points_word                      AS currency,
    rp.earned_date,
    rp.activity_date,
    rp.reward_reason,
    rp.event_id,

    -- Alternative reward columns (NULL if no alternative)
    ra.reward_name                      AS primary_reward,
    ra.reward_alternate_name            AS alternate_reward,
    ra.reward_alternate_identifier      AS alternate_code

FROM json_reward_points rp

-- LEFT JOIN: not every reward has an alternative
LEFT JOIN json_reward_alternative ra
    ON rp.member_id = ra.member_id
    AND rp.member_program_id = ra.member_program_id
    AND rp.member_reward_id = ra.member_reward_id

ORDER BY
    rp.member_id,
    rp.earned_date;


-- ============================================================================
-- QUERY 9: PROGRAM ENROLLMENT COUNTS
-- ============================================================================
-- What it does:
--   High-level summary of how many members are enrolled (active vs terminated)
--   in each program, along with aggregate point statistics.
--
-- Use this to:
--   - Get a quick snapshot of program participation
--   - Compare active vs terminated enrollment
--   - See average balances and earning rates per program
-- ============================================================================

SELECT
    p.program_name,
    p.internal_name,
    p.start_date                        AS program_start,
    p.end_date                          AS program_end,

    COUNT(DISTINCT m.member_id)         AS total_members,

    -- Active = no termination date
    COUNT(DISTINCT CASE
        WHEN m.termination_date IS NULL
        THEN m.member_id END)           AS active_members,

    -- Terminated = has a termination date
    COUNT(DISTINCT CASE
        WHEN m.termination_date IS NOT NULL
        THEN m.member_id END)           AS terminated_members,

    SUM(m.program_points_earned)        AS total_earned_all_members,
    SUM(m.program_points_redeemed)      AS total_redeemed_all_members,
    AVG(m.point_balance)                AS avg_current_balance

FROM json_programs m

JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id

GROUP BY
    p.program_name,
    p.internal_name,
    p.start_date,
    p.end_date

ORDER BY
    total_members DESC;


-- ============================================================================
-- QUERY 10: MEMBER-LEVEL DETAIL FOR A SPECIFIC PROGRAM
-- ============================================================================
-- What it does:
--   Template query to pull detailed earning history for all members in a
--   specific program. Replace the program_id filter with your target program.
--
-- Use this to:
--   - Generate a member-level detail report for a specific program
--   - Export for further analysis in Excel
--
-- HOW TO FIND YOUR PROGRAM_ID:
--   Run Query 1 (Program Catalog) and find the program_id for the program
--   you want to report on. Then paste it into the WHERE clause below.
-- ============================================================================

SELECT
    eh.member_id,
    eh.event_description                AS activity_completed,
    eh.event_timestamp                  AS activity_date,
    eh.incentives_timestamp             AS processed_date,
    CAST(eh.reward AS INT)              AS points_earned,
    eh.manually_fired                   AS was_manual,
    m.point_balance                     AS current_balance,
    m.program_points_earned             AS lifetime_earned

FROM json_earned_history eh

JOIN json_programs m
    ON eh.member_id = m.member_id
    AND eh.program_id = m.program_id
    AND eh.member_program_id = m.member_program_id

WHERE
    -- Replace with your target program_id from json_incentives_program_lu
    eh.program_id = '<YOUR_PROGRAM_ID_HERE>'

ORDER BY
    eh.member_id,
    eh.event_timestamp;



-- ============================================================================
-- QUERY 11: EARNING RATE BY EMPLOYER GROUP
-- ============================================================================
-- What it does:
--   Breaks down program participation and earning by employer_id. Shows how
--   many members per employer group are enrolled, how many have earned at
--   least once, and the average points per earner.
--
-- Use this to:
--   - Compare engagement across employer groups / subsidiaries
--   - Identify groups with low earning rates for targeted outreach
--   - Support employer-specific reporting
-- ============================================================================

SELECT
    m.employer_id,
    p.program_name,
    COUNT(DISTINCT m.member_id)         AS enrolled_members,

    -- Members who earned at least 1 point
    COUNT(DISTINCT CASE
        WHEN m.program_points_earned > 0
        THEN m.member_id END)           AS members_with_earnings,

    -- Earning rate: % of enrolled who have earned anything
    ROUND(
        COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END) * 100.0
        / NULLIF(COUNT(DISTINCT m.member_id), 0), 1
    )                                   AS earning_rate_pct,

    SUM(m.program_points_earned)        AS total_points_earned,

    -- Average points per member who has earned
    ROUND(
        SUM(m.program_points_earned) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN m.program_points_earned > 0 THEN m.member_id END), 0), 0
    )                                   AS avg_points_per_earner

FROM json_programs m
JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id
WHERE m.termination_date IS NULL        -- Active enrollments only
GROUP BY m.employer_id, p.program_name
ORDER BY enrolled_members DESC;


-- ============================================================================
-- QUERY 12: TOP EARNERS PER PROGRAM
-- ============================================================================
-- What it does:
--   Identifies the members with the highest lifetime earnings per program.
--   Useful for understanding power users and validating that no one has
--   exceeded program maximums.
--
-- Use this to:
--   - Identify highly engaged members
--   - Validate nobody has earned above the program max_points
--   - Support recognition or outreach programs
-- ============================================================================

SELECT
    m.member_id,
    p.program_name,
    m.program_points_earned             AS lifetime_earned,
    m.program_points_redeemed           AS lifetime_redeemed,
    m.point_balance                     AS current_balance,
    p.max_points                        AS program_maximum,

    -- Flag if member exceeded program max (data quality check)
    CASE
        WHEN m.program_points_earned > p.max_points
        THEN 'OVER MAX'
        ELSE 'OK'
    END                                 AS max_check

FROM json_programs m
JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id
WHERE m.program_points_earned > 0
ORDER BY m.program_points_earned DESC
LIMIT 100;


-- ============================================================================
-- QUERY 13: ACTIVITY COMPLETION FUNNEL
-- ============================================================================
-- What it does:
--   For each event in a program, shows how many members completed it. Helps
--   visualize the "funnel" — which activities have high vs low participation.
--   Also calculates the % of enrolled members who completed each activity.
--
-- Use this to:
--   - Build a completion funnel report
--   - Identify activities with low uptake
--   - Prioritize member communications
-- ============================================================================

SELECT
    p.program_name,
    e.event_group_name,
    eh.event_description                AS activity,
    COUNT(DISTINCT eh.member_id)        AS members_completed,

    -- Total enrolled in this program (subquery for the denominator)
    (SELECT COUNT(DISTINCT member_id)
     FROM json_programs
     WHERE program_id = eh.program_id
       AND termination_date IS NULL)    AS total_enrolled,

    -- Completion rate
    ROUND(
        COUNT(DISTINCT eh.member_id) * 100.0
        / NULLIF((SELECT COUNT(DISTINCT member_id)
                  FROM json_programs
                  WHERE program_id = eh.program_id
                    AND termination_date IS NULL), 0), 1
    )                                   AS completion_rate_pct

FROM json_earned_history eh
JOIN json_incentives_program_lu p
    ON eh.program_id = p.program_id
JOIN json_incentives_program_events_lu ev
    ON eh.program_id = ev.program_id
    AND eh.event_identifier = ev.event_secondary_identifier
JOIN json_incentives_program_event_group_lu e
    ON ev.program_id = e.program_id
    AND ev.event_group_id = e.event_group_id
GROUP BY
    p.program_name,
    e.event_group_name,
    eh.event_description,
    eh.program_id
ORDER BY
    p.program_name,
    completion_rate_pct DESC;


-- ============================================================================
-- QUERY 14: TIME TO FIRST EARNING
-- ============================================================================
-- What it does:
--   Calculates how long it takes a member from program enrollment (first
--   appearance in json_programs) to their first earning event. Helps measure
--   program activation speed.
--
-- Use this to:
--   - Measure onboarding effectiveness
--   - Identify programs where members take too long to engage
--   - Benchmark time-to-first-action across employer groups
-- ============================================================================

SELECT
    p.program_name,
    m.employer_id,
    COUNT(DISTINCT m.member_id)         AS members_with_earnings,

    -- Average days from enrollment to first earning
    AVG(DATEDIFF('day',
        CAST(m.last_updated_date AS DATE),
        CAST(first_earn.first_earn_date AS DATE)
    ))                                  AS avg_days_to_first_earn,

    -- Median approximation: use percentile if available, otherwise min/max
    MIN(DATEDIFF('day',
        CAST(m.last_updated_date AS DATE),
        CAST(first_earn.first_earn_date AS DATE)
    ))                                  AS fastest_days,

    MAX(DATEDIFF('day',
        CAST(m.last_updated_date AS DATE),
        CAST(first_earn.first_earn_date AS DATE)
    ))                                  AS slowest_days

FROM json_programs m

-- Subquery: first earning date per member per program
JOIN (
    SELECT
        member_id,
        program_id,
        member_program_id,
        MIN(incentives_timestamp)       AS first_earn_date
    FROM json_earned_history
    GROUP BY member_id, program_id, member_program_id
) first_earn
    ON m.member_id = first_earn.member_id
    AND m.program_id = first_earn.program_id
    AND m.member_program_id = first_earn.member_program_id

JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id

GROUP BY p.program_name, m.employer_id
ORDER BY avg_days_to_first_earn;


-- ============================================================================
-- QUERY 15: REDEMPTION TIMING ANALYSIS
-- ============================================================================
-- What it does:
--   Analyzes when members redeem relative to when they earn. Shows the average
--   number of days between the last earning and a redemption, plus monthly
--   redemption volume.
--
-- Use this to:
--   - Understand member redemption behavior
--   - Forecast future redemption liability
--   - Identify programs where members hoard vs spend quickly
-- ============================================================================

SELECT
    p.program_name,
    LEFT(rh.redemption_date, 7)         AS redemption_month,
    COUNT(*)                            AS redemption_count,
    COUNT(DISTINCT rh.member_id)        AS unique_redeemers,
    SUM(rh.points_redeemed)             AS total_points_redeemed,
    AVG(rh.points_redeemed)             AS avg_points_per_redemption

FROM json_redemption_history rh
JOIN json_incentives_program_lu p
    ON rh.program_id = p.program_id
GROUP BY
    p.program_name,
    LEFT(rh.redemption_date, 7)
ORDER BY
    p.program_name,
    redemption_month;


-- ============================================================================
-- QUERY 16: POINTS LIABILITY REPORT
-- ============================================================================
-- What it does:
--   Calculates the total outstanding point liability across all active members.
--   Groups by program and shows total unredeemed balance, the dollar value
--   (using point_monetary_value from program config), and member count.
--
-- Use this to:
--   - Understand financial liability from unredeemed points
--   - Report to finance/actuarial teams
--   - Track liability trends over time
--
-- NOTE: point_monetary_value of 0 means the program uses a marketplace
--       redemption model (ADR) where dollar value varies by product selected.
-- ============================================================================

SELECT
    p.program_name,
    p.rewards_provider,
    p.point_monetary_value,
    COUNT(DISTINCT m.member_id)         AS active_members_with_balance,
    SUM(m.point_balance)                AS total_outstanding_points,

    -- Dollar liability (only meaningful when point_monetary_value > 0)
    CASE
        WHEN p.point_monetary_value > 0
        THEN SUM(m.point_balance) * p.point_monetary_value
        ELSE NULL
    END                                 AS estimated_dollar_liability

FROM json_programs m
JOIN json_incentives_program_lu p
    ON m.program_id = p.program_id
WHERE m.point_balance > 0
  AND m.termination_date IS NULL
GROUP BY
    p.program_name,
    p.rewards_provider,
    p.point_monetary_value
ORDER BY
    total_outstanding_points DESC;


-- ============================================================================
-- QUERY 17: MANUAL ADJUSTMENT AUDIT
-- ============================================================================
-- What it does:
--   Lists all manual adjustments with context. Groups by description/reason
--   to identify patterns (bulk corrections, refunds, etc.).
--
-- Use this to:
--   - Audit administrative point changes
--   - Track refunds and corrections
--   - Identify recurring issues requiring manual intervention
-- ============================================================================

SELECT
    p.program_name,
    ma.description                      AS adjustment_reason,
    COUNT(*)                            AS adjustment_count,
    COUNT(DISTINCT ma.member_id)        AS members_affected,
    SUM(ma.points_adjusted)             AS net_points_adjusted,
    MIN(ma.incentives_timestamp)        AS first_adjustment,
    MAX(ma.incentives_timestamp)        AS last_adjustment

FROM json_manual_adjustment_history ma
JOIN json_incentives_program_lu p
    ON ma.program_id = p.program_id
GROUP BY
    p.program_name,
    ma.description
ORDER BY
    ABS(SUM(ma.points_adjusted)) DESC;


-- ============================================================================
-- QUERY 18: EXPIRATION RISK REPORT
-- ============================================================================
-- What it does:
--   Identifies members whose points have expired and the volume of expirations
--   by program and month. Useful for understanding if members are losing value
--   and whether communication about upcoming expirations is effective.
--
-- Use this to:
--   - Track how many points are being lost to expiration
--   - Identify programs with high expiration rates
--   - Build a case for reminder communications
-- ============================================================================

SELECT
    p.program_name,
    LEFT(ex.expiration_date, 7)         AS expiration_month,
    COUNT(*)                            AS expiration_events,
    COUNT(DISTINCT ex.member_id)        AS members_affected,
    SUM(ex.points_expired)              AS total_points_expired

FROM json_expiration_history ex
JOIN json_incentives_program_lu p
    ON ex.program_id = p.program_id
GROUP BY
    p.program_name,
    LEFT(ex.expiration_date, 7)
ORDER BY
    p.program_name,
    expiration_month;


-- ============================================================================
-- QUERY 19: PROGRAM YEAR-OVER-YEAR COMPARISON
-- ============================================================================
-- What it does:
--   Compares earning activity between two time periods (e.g., this year vs
--   last year) to show growth or decline. Adjust the date filters as needed.
--
-- Use this to:
--   - Compare program performance across years
--   - Demonstrate growth in executive reports
--   - Identify declining programs
-- ============================================================================

SELECT
    p.program_name,
    eh.event_description,

    -- Current year metrics
    COUNT(DISTINCT CASE
        WHEN LEFT(eh.incentives_timestamp, 4) = '2026'
        THEN eh.member_id END)          AS members_2026,
    SUM(CASE
        WHEN LEFT(eh.incentives_timestamp, 4) = '2026'
        THEN CAST(eh.reward AS INT) ELSE 0 END) AS points_2026,

    -- Prior year metrics
    COUNT(DISTINCT CASE
        WHEN LEFT(eh.incentives_timestamp, 4) = '2025'
        THEN eh.member_id END)          AS members_2025,
    SUM(CASE
        WHEN LEFT(eh.incentives_timestamp, 4) = '2025'
        THEN CAST(eh.reward AS INT) ELSE 0 END) AS points_2025,

    -- Year-over-year change
    ROUND(
        (SUM(CASE WHEN LEFT(eh.incentives_timestamp, 4) = '2026' THEN CAST(eh.reward AS INT) ELSE 0 END)
       - SUM(CASE WHEN LEFT(eh.incentives_timestamp, 4) = '2025' THEN CAST(eh.reward AS INT) ELSE 0 END))
       * 100.0
       / NULLIF(SUM(CASE WHEN LEFT(eh.incentives_timestamp, 4) = '2025' THEN CAST(eh.reward AS INT) ELSE 0 END), 0)
    , 1)                                AS yoy_change_pct

FROM json_earned_history eh
JOIN json_incentives_program_lu p
    ON eh.program_id = p.program_id
WHERE LEFT(eh.incentives_timestamp, 4) IN ('2025', '2026')
GROUP BY
    p.program_name,
    eh.event_description
HAVING
    -- Only show activities with data in at least one year
    SUM(CASE WHEN LEFT(eh.incentives_timestamp, 4) = '2025' THEN 1 ELSE 0 END) > 0
    OR SUM(CASE WHEN LEFT(eh.incentives_timestamp, 4) = '2026' THEN 1 ELSE 0 END) > 0
ORDER BY
    p.program_name,
    yoy_change_pct DESC;


-- ============================================================================
-- QUERY 20: MEMBER ENGAGEMENT SEGMENTATION
-- ============================================================================
-- What it does:
--   Segments members into engagement tiers based on their earning behavior:
--     - Power Users: earned 75%+ of program max
--     - Active: earned 25-75% of max
--     - Low: earned 1-25% of max
--     - Inactive: enrolled but earned nothing
--
-- Use this to:
--   - Build engagement tiers for reporting
--   - Target communications by segment
--   - Track segment migration over time
-- ============================================================================

SELECT
    p.program_name,
    segment,
    COUNT(*)                            AS member_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY p.program_name), 1)
                                        AS pct_of_enrolled,
    AVG(program_points_earned)          AS avg_points,
    AVG(point_balance)                  AS avg_balance

FROM (
    SELECT
        m.*,
        p2.max_points,
        CASE
            WHEN m.program_points_earned = 0 THEN 'Inactive'
            WHEN m.program_points_earned < p2.max_points * 0.25 THEN 'Low'
            WHEN m.program_points_earned < p2.max_points * 0.75 THEN 'Active'
            ELSE 'Power User'
        END AS segment
    FROM json_programs m
    JOIN json_incentives_program_lu p2 ON m.program_id = p2.program_id
    WHERE m.termination_date IS NULL
      AND p2.max_points > 0
) segmented

JOIN json_incentives_program_lu p
    ON segmented.program_id = p.program_id

GROUP BY p.program_name, segment
ORDER BY p.program_name,
    CASE segment
        WHEN 'Power User' THEN 1
        WHEN 'Active' THEN 2
        WHEN 'Low' THEN 3
        WHEN 'Inactive' THEN 4
    END;
