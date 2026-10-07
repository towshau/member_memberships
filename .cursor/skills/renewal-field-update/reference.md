# Renewal field reference

Read this when drafting an outline or SQL. Renewal = `member_renewal_meta` + linked `member_memberships`.

## member_memberships

Writable unless noted.

| Column | Type | Notes |
|---|---|---|
| id | uuid | Never update. PK. |
| member_id | uuid | FK `member_database`. Also fires referral leaderboard sync. |
| membership_type_id | uuid | FK `membership_types`. |
| start_date | date | Required. Syncs journey notification, referral leaderboard, and member coach. |
| end_date | date | Required. Syncs journey notification and member coach. With `journey_stage = not_renewing` and `end_date < current_date`, status becomes `inactive` and may set `member_database.current_status`. |
| status | text | `active`, `inactive`, `pending`, `F&F`, `indefinite_hold`. Setting `indefinite_hold` stamps `indefinite_hold_at = now()` when it was not already that status. |
| created_at | timestamptz | Leave unchanged unless named in the outline. |
| test_duration | text | |
| member_name | text | Denormalized. |
| coach_id | uuid | FK `staff_database`. Syncs journey notification and member coach. |
| salesperson_id | uuid | FK `staff_database`. |
| membership_stage | text | Free text pipeline label. |
| newsale_metadata | uuid | FK `member_newsale_metadata`. Do not edit that table in this skill. |
| renewal_metadata | uuid | FK `member_renewal_meta`. `ON UPDATE CASCADE`. `ON DELETE CASCADE` from the meta row deletes this membership. |
| journey_stage | journey_stage_type | See side effects below. |
| gym | text | |
| programming_coach_id | uuid | FK `staff_database`. |
| handoff_coach_id | uuid | FK `staff_database`. Current coach is `COALESCE(handoff_coach_id, coach_id)`. Syncs journey notification and member coach. |
| revenue_team_assignee | uuid | FK `staff_database`. |
| renewal_assignee | uuid | FK `staff_database`. |
| nutrition_lead | uuid | FK `staff_database`. |
| pipeline_lost | pipelinelost_churnmarker | `good_churn`, `bad_churn`, or null. Trigger sets or clears `pipeline_lost_set_at`. |
| membership_notes | text | |
| primary_membership_id | uuid | Null on a primary. Set on a secondary. Syncs referral leaderboard and member coach. |
| check1, check2, check3 | boolean | |
| renewal_date | date | |
| rm | boolean | Not null, default true. |
| vo2_membership_choice | text | `yes`, `no`, `upsell_later`, or null. |
| vo2_membership_choice_notes | text | |
| indefinite_hold_at | timestamptz | Trigger-owned when status becomes `indefinite_hold`. |
| contra_deal_id | uuid | FK `member_contra_deals`. Same member required. |
| pipeline_lost_set_at | timestamptz | Trigger-owned when `pipeline_lost` changes. |

`journey_stage` values: `trial`, `first_30`, `new_member`, `awaiting_call`, `called_nobooking`, `booked`, `renewal_complete`, `renew_30`, `renewed_member`, `non_core_membership`, `expired`, `not_renewing`, `no_sale`, `unknown`, `deciding`.

## member_renewal_meta

| Column | Type | Notes |
|---|---|---|
| id | uuid | Never update. PK. |
| membership_selected | text | |
| expiry_date | timestamptz | Can set `holds_policy_fk` and rewrite `holds_agreement`. |
| cohort_start_date | timestamptz | |
| date_created | timestamp | Leave unchanged unless named in the outline. |
| member_name | text | Denormalized. |
| ongoing_coach_email | text | |
| session_credits | numeric | Recalc trigger. |
| client_email | text | |
| coach_name | text | Denormalized. Update when `coach_id` changes. |
| membership_weeks | numeric | Recalc trigger. |
| hold_value | numeric | |
| base_membership_value | numeric | Value before add-ons or discounts; holds are not subtracted. Recalc trigger. |
| holds_agreement | text | May be overwritten from `holds_policy_fk`. |
| membership_duration | text | |
| gym | text | |
| price_paid | numeric | |
| addons | text | |
| old_coach_email | text | |
| sales_person | text | Denormalized salesperson name. |
| created_data_entry | timestamptz | Leave unchanged unless named in the outline. |
| total_sessions | smallint | Recalc fills this only when it is null: `round(membership_weeks * session_credits)`. |
| per_session_value | numeric | Recalc sets `round(base_membership_value / total_sessions, 2)` when weeks, credits, or base value change. |
| member_id | uuid | FK `member_database`. Keep aligned with the membership. |
| coach_id | uuid | FK `staff_database`. |
| salesperson_id | uuid | FK `staff_database`. |
| membership_type_id | uuid | FK `membership_types`. |
| renewal_duration_points | numeric | |
| psv_norm | numeric | Stored generated. Never write. `((base_membership_value - (membership_weeks * 130)) / total_sessions)`. |
| holds_policy_fk | uuid | FK `holds_policies`. Setting it rewrites `holds_agreement`. |
| secondary_memberships | text | |
| secondary_membership_session_per_week | numeric | |
| charge_1_amount | numeric | First scheduled or paid charge. |
| charge_1_date | date | |
| pp_less_family | numeric | Price paid excluding family add-on. |

Known holds policies, used when `holds_policy_fk` is null, `expiry_date` is still in the future, and `holds_agreement` contains the percent:

- `100%` → `7b767169-4a3c-4730-8fa0-0ee1d6c0bbad`
- `95%` → `0516a908-00da-405f-9c96-21d5e9b7164c`
- `75%` → `d772dede-52dd-4aa9-99bb-93657de7f730`

After the policy is set, `holds_agreement` is replaced with the policy's canonical text.

## Side effects to list in the outline

`member_memberships.journey_stage`:

- `renewed_member`: previous primary (matching stage and date rules) becomes `renewal_complete`. Secondaries linked to that previous primary get `journey_stage` null.
- `not_renewing`: upserts `member_not_renewing`. If `end_date < current_date`, this row's `status` becomes `inactive`. Without another future membership, `member_database.current_status` becomes `inactive`.
- `no_sale`: this row's `status` becomes `inactive` and `member_database.current_status` becomes `inactive`.
- `expired`: this row's `status` becomes `inactive`. `member_database.current_status` becomes `inactive` unless a future membership or `renewed_member` rule sets the member active.
- `not_renewing`, `no_sale`, or `expired`: posts a Pabbly webhook (`fn_membership_journey_webhook`).
- Any journey_stage change, and any change to `start_date`, `end_date`, `coach_id`, or `handoff_coach_id`: syncs member journey notification.
- `handoff_coach_id`, `coach_id`, `start_date`, `end_date`, or `primary_membership_id`: syncs the member's current coach from the handoff coach.
- `member_id`, `start_date`, or `primary_membership_id`: syncs the referral leaderboard.

`member_renewal_meta`:

- Update of `membership_weeks`, `session_credits`, or `base_membership_value` recalculates `per_session_value` and, only when `total_sessions` is null, fills `total_sessions`. `psv_norm` regenerates.
- Update of `holds_agreement`, `expiry_date`, or `holds_policy_fk` may set the policy and overwrite `holds_agreement`.

## Staff lookup

```sql
SELECT id, coach_name, first_name
FROM public.staff_database
WHERE coach_name ILIKE '%' || '<name>' || '%'
ORDER BY coach_name;
```

If more than one row matches, ask which id before the outline.
