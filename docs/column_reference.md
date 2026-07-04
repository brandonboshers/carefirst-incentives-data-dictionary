# Column Reference

Every column in every file. Use this as a lookup when building queries.

---

## json_incentives_program_lu

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

## json_incentives_program_event_group_lu

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

## json_incentives_program_events_lu

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

## json_programs

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

## json_ag_incentives

| Column | Type | What It Is |
|--------|------|-----------|
| member_id | varchar | The member |
| incentives_activated | varchar | Are incentives turned on? (true/false) |

## json_earned_history

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

## json_event_history

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

## json_redemption_history

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

## json_expiration_history

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

## json_manual_adjustment_history

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

## json_reward_points

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

## json_reward_alternative

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

## json_redemption_history_product

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
