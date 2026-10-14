---
name: no-sale
description: >-
  Closes a membership as a no sale: sets the primary journey_stage to no_sale,
  sets the primary and each secondary status to inactive, records a reactivation date or 0%
  probability with no date, writes member_not_renewing so the client-exit Slack
  includes gym and payment details, and sets the Payment Success tracker to No
  Sale. Use only when Yam tags Cursor and says run no sale skill.
disable-model-invocation: true
---

# No sale

Run this only when Yam tags Cursor and says **run no sale skill**.

The source is the original message in the thread (the note Yam is reacting to). "Run no sale skill" is the instruction to apply that note. It is not the source of the member, the reason, or the date.

## What to do

1. Read the rows. Do not write yet.
2. Set `journey_stage` to `no_sale` on the primary only. Leave every secondary `journey_stage` unchanged. Set `status` to `inactive` on the primary and on each linked secondary. The primary update also sets `member_database.current_status` to `inactive`.
3. Upsert `member_not_renewing` on the primary in one request. Insert a reactivation date if one was listed in the original message otherwise mark as 0% probability with no date. That insert or update fires the client-exit Slack with the payment detail block, and sets the linked Payment Success tracker `payment_status` to `No Sale`.
4. Reply in this thread with the info Jathy needs.

## Stop before writing

- The original message names no member. Ask which member.
- The name matches more than one person. List them and ask which one.
- There is no newsale primary with `start_date` in the last 30 days. Say so and stop. No sale is only tagged on a newsale inside that window.
- More than one newsale primary has `start_date` in the last 30 days. That is a duplicate. List `membership_id`, type, start, end, status, and `journey_stage`, then ask which primary.
- More than one `payment_success_tracker` row has that primary's `membership_id`. List the tracker ids, amounts, and payment dates, then ask which row. Do not write yet.
- The member has another membership that should stay open: `status` in `active`, `pending`, `F&F`, or `indefinite_hold`, and the row is not this newsale primary or a secondary of it. List it and wait. Setting `no_sale` marks the whole member inactive.

## Database access

On Slack, do not use the Supabase MCP and do not ask anyone to log in to Supabase.

Read and write only with `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. Pass the key only as `$SUPABASE_SERVICE_ROLE_KEY`. Never use the anon or publishable key. Never print the service role key.

If either variable is unset, stop and say to add both under Cloud Agent secrets for the Slack Cursor account. Do not guess the row.

```bash
curl -sS "$SUPABASE_URL/rest/v1/member_memberships?member_name=ilike.*Andrew%20Connole*&select=id,member_id,member_name,status,journey_stage,membership_stage,start_date,end_date,gym,primary_membership_id,coach_id,handoff_coach_id,programming_coach_id,renewal_assignee,revenue_team_assignee,salesperson_id,membership_type_id&order=end_date.desc" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Accept: application/json"
```

Then load, for that `member_id`:

- every `member_memberships` row (primary and secondaries)
- `member_database`: `id`, `member_name`, `current_status`
- `member_not_renewing` where `membership_id` is the primary (`UNIQUE` on `membership_id`)
- `payment_success_tracker` where `membership_id` is the primary, and any other rows for that `member_id`
- `membership_types.name` for each membership
- current coach name: `staff_database.coach_name` for `COALESCE(handoff_coach_id, coach_id)`
- salesperson name: `staff_database.coach_name` for `salesperson_id`
- `payment_success_tracker` for that membership: `id`, `payment_status`, `payment_method`, `amount`, `payment_date`, `notes`
- card last 4, in this order: `stripe_invoices.last_4_digits` for the membership, default `member_stripe_payment_methods.last_4_digits`, `member_credit_card.last_4_digits`, `member_payment_method.last_4_digits`
- paying entity on file: `stripe_invoices.billing_name` or `customer_name` for the membership, else `stripe_customers.billing_name`

The no-sale primary is the one row with `primary_membership_id` null, `membership_stage` `newsale`, and `start_date` on or after 30 days ago. A newsale inside that window is the only membership that gets `no_sale`. Secondaries are rows whose `primary_membership_id` is that primary. They are not a second newsale.

The Payment Success tracker row is the one `payment_success_tracker` row with `membership_id` equal to that primary. Tracker rows for an older membership stay as they are. One tracker row is the normal case. Two rows on that same membership are a duplicate, so stop and ask.

## Membership details

PATCH the primary only. Do not send `journey_stage` for a secondary.

```bash
curl -sS -X PATCH "$SUPABASE_URL/rest/v1/member_memberships?id=eq.<primary_id>" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"journey_stage":"no_sale"}'
```

`trigger_set_status_inactive_on_no_sale` sets the primary `status` to `inactive` and `member_database.current_status` to `inactive`. Skip this PATCH when the primary is already `journey_stage = no_sale` and `status = inactive`.

Then PATCH each linked secondary whose `status` is not already `inactive`. Send `status` only.

```bash
curl -sS -X PATCH "$SUPABASE_URL/rest/v1/member_memberships?id=eq.<secondary_id>" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"status":"inactive"}'
```

Side effect when the primary `journey_stage` actually changes to `no_sale`: `fn_membership_journey_webhook` posts that primary to Pabbly. Secondaries do not post. Say so in the reply.

Do not call `submit_client_exit_form`. The no-sale Slack is fired by the `member_not_renewing` write below. Calling the form as well sends Jathy a second message, and that function does not save the reactivation row.

Do not set `journey_stage` to `not_renewing`. That opens a different exit path. The not-renewing "accounts ready to close" Slack still fires from `submit_client_exit_form` when `can_close_accounts` becomes `yes`.

## Reactivation date

Write this on the primary's `member_not_renewing` row only.

Insert a reactivation date if one was listed in the original message otherwise mark as 0% probability with no date.

| Original message | `confirmation_date` | `estimated_return_12_months` |
|---|---|---|
| A calendar date | That date | Leave as stated in the message. If no percent was stated, leave null. |
| A month and no day | The 15th of that month. If that month is already past, use next year. | Same as above. |
| No date and no month | `null` | `0` |

`confirmation_date` is the reactivation date. `estimated_return_12_months` is the percent (`0`, `5`, `25`, `50`, `95` are the values in use).

`reactivation_notes` is the reason from the original message, plus two lines the database cannot look up. Do not include "run no sale skill". Do not repeat gym, payment method, card digits, amount, salesperson, or coach. The trigger appends those to the Slack note.

Always include these two lines. Take the words from the original message. If it does not state one, write `not stated`.

```
Refund: <full or partial, with the amount. Example: full $18839.50, or partial after sessions used>
Paying entity: <invoice or company name. Example: Sonoma Bakery Pty Ltd>
```

The trigger then adds this block to the webhook note. A missing database value is `not on file`. It does not replace a `Refund:` or `Paying entity:` line already in the notes.

```
Gym: <membership gym>
Payment method: <card, ACH, invoice, or the stored method>
Card last 4: <digits>
Amount paid: <$amount on payment date>
Salesperson: <salesperson name>
Coach: <handoff coach, else primary coach>
```

`Credit Card`, `Stripe - CC`, `Square`, and `Virtual Terminal` are sent as `card`. `ACH` and `BECS` are sent as `ACH`. `Invoice Send` is sent as `invoice`.

That text must be in the same insert or update as `no_sale`, the date, and the percent. A second write that only repeats those values does not send another Slack. Changing any of them later does.

The same write sets `payment_success_tracker.payment_status` to `No Sale` on the tracker row whose `membership_id` is that primary. Do not PATCH the tracker yourself. If more than one tracker row is linked to that primary, stop before this write.

`logged_by_staff_id` is who the Slack names as submitter. On insert, set Yam Lim (`85410c9b-39e1-45ba-b4d9-cf4c84893022`) unless the original message names a different staff member. On update, set it only when it is null.

No row yet: POST one. Copy coach fields from the primary. Set `no_sale` to `true`.

```bash
curl -sS -X POST "$SUPABASE_URL/rest/v1/member_not_renewing" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "membership_id": "<primary_id>",
    "member_id": "<member_id>",
    "member_name": "<member_name>",
    "coach_id": "<coach_id or null>",
    "handoff_coach_id": "<handoff_coach_id or null>",
    "programming_coach_id": "<programming_coach_id or null>",
    "renewal_assignee": "<renewal_assignee or null>",
    "revenue_team_assignee": "<revenue_team_assignee or null>",
    "salesperson_id": "<salesperson_id or null>",
    "no_sale": true,
    "confirmation_date": null,
    "estimated_return_12_months": 0,
    "reactivation_notes": "<notes>",
    "logged_by_staff_id": "85410c9b-39e1-45ba-b4d9-cf4c84893022"
  }'
```

That POST or PATCH queues the client-exit Slack (`private.notify_client_exit_n8n`, kind `no_sale`) through `trg_client_exit_slack_from_not_renewing`. Do not call the webhook yourself.

Row already exists: PATCH by `id`. Set `no_sale` true, `confirmation_date`, `estimated_return_12_months`, and `reactivation_notes` in that one request. Refresh the coach ids from the primary. Leave reason and follow-up columns unchanged. Leave `logged_by_staff_id` unchanged when it is already set.

Omit JSON keys whose value is null only when the column should stay unchanged. Send `confirmation_date: null` when the rule above clears the date.

## Reply

Post this in the thread after the writes. Tag Jathy (`<@U05578X04Q7>`). Use the original message. If a fact was not stated, write "not stated". Do not invent a refund, an amount, or a date.

```
*<@U05578X04Q7> No sale*

Member: <member_name>
Gym: <gym>
Coach: <current coach name>
Primary: `<membership_id>` — <membership type>, <start> to <end>
Linked: <each secondary, or "none">

*Closed*
• primary journey_stage → `no_sale`
• secondary journey_stage unchanged
• status → `inactive` on the primary and each secondary
• member current_status → `inactive` (trigger)
• Pabbly webhook: <ids that changed, or "none — already no_sale">
• Client-exit Slack: sent from the `member_not_renewing` write

*For Jathy*
• Why: <reason from the original message>
• Refund: <the Refund line sent>
• Paying entity: <the Paying entity line sent>
• Gym: <gym>
• Payment method: <card, ACH, invoice, or stored method>
• Card last 4: <digits or not on file>
• Amount paid: <amount on date, or not on file>
• Salesperson: <name>
• Coach: <name>
• Reactivation: <confirmation_date, and say when the day was assumed as the 15th> or `0% probability, no date`

*Payment Success tracker*
• `<tracker id>`: payment_status `<previous>` → `No Sale`
• If no row is linked to this membership, say so.
```

One member per reply. A batch is one reply with a section per member, still only after each member resolved to one primary.

## Rules

- Never `DELETE` `member_not_renewing` or `member_memberships`.
- Never update `id`.
- Do not write `member_newsale_metadata` or `member_renewal_meta` here.
- Do not change `membership_stage`, dates, coach, or price unless the original message says to and Yam included that in the run instruction.
- Staff and membership ids must already exist. Do not invent uuids.
- One primary per run unless the message names several members and each resolves cleanly.
