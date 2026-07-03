# CareFirst Incentives JSON Data Documentation

Documentation and example SQL queries for the 13 incentive-related JSON data files delivered as part of the CareFirst/Sharecare integration.

---

## Contents

| Path | Description |
|------|-------------|
| [docs/data_dictionary.md](docs/data_dictionary.md) | Full data dictionary — file descriptions, join keys, example queries, key concepts, and complete column definitions for all 13 files |
| [sql/example_queries.sql](sql/example_queries.sql) | 20 ready-to-use SQL queries with detailed comments explaining logic, joins, and how to adapt for reporting |

---

## Quick Start

1. **Understand the files** — Start with the [Data Dictionary](docs/data_dictionary.md). It explains what each file contains, how they relate, and how to join them.

2. **Run example queries** — Open [example_queries.sql](sql/example_queries.sql) in your SQL tool. Each query has a block comment explaining what it does, when to use it, and how to customize it.

3. **Build your own reports** — Use the Join Keys table and the example patterns as building blocks for custom reporting.

---

## Files Covered

### Program Configuration (Lookup/Reference)
- `json_incentives_program_lu` — Program definitions
- `json_incentives_program_event_group_lu` — Event group definitions
- `json_incentives_program_events_lu` — Individual event definitions

### Member Enrollment
- `json_programs` — Member program enrollments
- `json_ag_incentives` — Member activation flag

### Transaction History
- `json_earned_history` — Points awarded
- `json_event_history` — Raw events received
- `json_redemption_history` — Points redeemed
- `json_expiration_history` — Points expired
- `json_manual_adjustment_history` — Admin adjustments

### Reward Details
- `json_reward_points` — Reward earning details
- `json_reward_alternative` — Non-standard rewards (co-pay reductions, etc.)
- `json_redemption_history_product` — Marketplace product line items

---

## Example Queries Included

| # | Query | Purpose |
|---|-------|---------|
| 1 | Program Catalog | Full program structure with events |
| 2 | Member Enrollment Summary | Balances and lifetime totals |
| 3 | Points Earned by Activity | Aggregate earning by event |
| 4 | Monthly Earning Trend | Time-series engagement |
| 5 | Redemption by Product | What members redeem for |
| 6 | Full Point Lifecycle | Complete audit trail (union) |
| 7 | Events That Did Not Earn | Gap analysis |
| 8 | Reward Details with Alternatives | Non-point rewards |
| 9 | Program Enrollment Counts | Active vs terminated |
| 10 | Member Detail for a Program | Template for custom pulls |
| 11 | Earning Rate by Employer | Group-level engagement |
| 12 | Top Earners | Power users + max validation |
| 13 | Activity Completion Funnel | % completion per activity |
| 14 | Time to First Earning | Onboarding speed |
| 15 | Redemption Timing | Monthly redemption volume |
| 16 | Points Liability Report | Outstanding balance + $ value |
| 17 | Manual Adjustment Audit | Admin correction tracking |
| 18 | Expiration Risk Report | Points lost over time |
| 19 | Year-Over-Year Comparison | YoY growth/decline |
| 20 | Member Engagement Segmentation | Power User / Active / Low / Inactive |

---

## Data Type Notes

- **Dates** — Stored as varchar in `YYYY-MM-DD HH:MI:SS` format. Cast to DATE/TIMESTAMP as needed.
- **IDs** — MongoDB hex strings (varchar). Join on exact string match.
- **member_id** — Numeric string (Sharecare member identifier).
- **reward** (in earned_history) — Varchar. Cast to INT for sums.

---

## Questions?

Contact your Sharecare Client Reporting team representative.
