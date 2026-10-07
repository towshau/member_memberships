---
name: renewal-field-update
description: >-
  Updates any writable field on a renewal across public.member_renewal_meta and
  public.member_memberships. Use when a Cursor cloud agent or Claude is asked to
  change a renewal, renewal metadata, membership dates, journey stage, coach,
  price, charges, holds, or any other column on those two tables. Always outline
  the proposed changes for Yam's approval in Slack and wait; write only after
  Yam approves in that thread.
---

# Renewal field update

Renewal = `public.member_renewal_meta` and the linked `public.member_memberships` row (`member_memberships.renewal_metadata` → `member_renewal_meta.id`).

This skill may update **any writable column** on those two tables. It may also insert a `member_renewal_meta` row and set `renewal_metadata` when the membership has none. Column list, enums, and trigger side effects are in [reference.md](reference.md).

## Process

Outline the proposed changes in here for approval then you approve changes, for Yam's approval in Slack.

1. Read the current rows. Do not write.
2. Post the Slack outline in this thread and stop.
3. Apply the outlined SQL only after Yam approves in this same thread.

The original request is not approval. "Update end date to 1 Apr" is the request. Approval is a later reply to the outline (`approve`, `approved`, `yes apply`, or an equivalent clear yes). If Yam changes the request, post a revised outline and wait again.

## Resolve the row

Use Supabase `execute_sql`. If the member name matches more than one membership, list them and ask which `membership_id` before drafting the outline.

```sql
SELECT
  mm.id AS membership_id,
  mm.member_name,
  mm.status,
  mm.journey_stage,
  mm.start_date,
  mm.end_date,
  mm.primary_membership_id,
  mm.renewal_metadata
FROM public.member_memberships mm
WHERE mm.member_name ILIKE '%' || '<name>' || '%'
ORDER BY mm.end_date DESC NULLS LAST;
```

Then load the full membership row and, when `renewal_metadata` is not null, the full `member_renewal_meta` row (`SELECT *`). Resolve staff names to `staff_database.id` and membership type names to `membership_types.id` before the outline, so Yam sees the name and the uuid.

## Slack outline

Post this and nothing else that writes data. Include only fields that will change. Quote current and proposed values. Call out every side effect from [reference.md](reference.md) that the change will fire.

```
*Renewal update — Yam's approval*

Member: <member_name>
Membership: `<membership_id>`
Renewal meta: `<renewal_metadata or none>`

*member_memberships*
• <column>: `<current>` → `<proposed>`

*member_renewal_meta*
• <column>: `<current>` → `<proposed>`

*Side effects*
• <what else will change, or "none">

Reply *approve* to apply this exact change.
```

Omit a table section when that table has no changes. For an insert, list every column that will be written and the `renewal_metadata` link.

## Apply

After approval, run one transaction. Update by primary key only. Set only columns that were in the approved outline.

```sql
BEGIN;

UPDATE public.member_memberships
SET <col> = <value>
WHERE id = '<membership_id>'::uuid;

UPDATE public.member_renewal_meta
SET <col> = <value>
WHERE id = '<renewal_metadata>'::uuid;

COMMIT;
```

Read both rows back and reply with the columns that changed, including values a trigger rewrote. If a trigger result differs from the outline, say so.

## Rules

- Never `DELETE` `member_renewal_meta`. That foreign key is `ON DELETE CASCADE` and deletes the membership.
- Never update `id`. Never write `member_renewal_meta.psv_norm` (stored generated).
- Leave `created_at`, `date_created`, and `created_data_entry` unchanged unless Yam named them in the outline.
- Leave `indefinite_hold_at` and `pipeline_lost_set_at` to their triggers unless the outline sets them on purpose.
- `vo2_membership_choice` is only `yes`, `no`, `upsell_later`, or null.
- `journey_stage` must be a `journey_stage_type` value. `pipeline_lost` is only `good_churn`, `bad_churn`, or null.
- `status` in use: `active`, `inactive`, `pending`, `F&F`, `indefinite_hold`.
- Staff and membership-type ids must already exist. Do not invent uuids.
- If `coach_id` or `salesperson_id` changes, include the matching denormalized name in the same outline.
- One membership per outline. A batch is one outline with a section per membership, still applied only after one approval.
- Do not update `member_newsale_metadata` here.
