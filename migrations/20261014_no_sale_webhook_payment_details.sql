-- Append gym, payment, payer, salesperson, and coach to the no-sale Slack note,
-- and mark the linked Payment Success tracker row as No Sale.

CREATE OR REPLACE FUNCTION private.trg_client_exit_slack_from_not_renewing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'net'
AS $$
DECLARE
  v_notes text;
  v_gym text;
  v_method text;
  v_method_label text;
  v_last4 text;
  v_amount numeric;
  v_paid_on text;
  v_salesperson text;
  v_coach text;
  v_payer text;
  v_amount_line text;
  v_block text;
BEGIN
  IF NEW.membership_id IS NULL OR NOT COALESCE(NEW.no_sale, false) THEN
    RETURN NEW;
  END IF;

  IF NOT (
    TG_OP = 'INSERT'
    OR NEW.no_sale IS DISTINCT FROM OLD.no_sale
    OR NEW.reactivation_notes IS DISTINCT FROM OLD.reactivation_notes
    OR NEW.confirmation_date IS DISTINCT FROM OLD.confirmation_date
    OR NEW.estimated_return_12_months IS DISTINCT FROM OLD.estimated_return_12_months
  ) THEN
    RETURN NEW;
  END IF;

  UPDATE public.payment_success_tracker
  SET payment_status = 'No Sale'
  WHERE membership_id = NEW.membership_id
    AND payment_status IS DISTINCT FROM 'No Sale';

  SELECT
    COALESCE(NULLIF(btrim(mm.gym), ''), NULLIF(btrim(pst.gym), '')),
    NULLIF(btrim(pst.payment_method), ''),
    pst.amount,
    NULLIF(btrim(pst.payment_date), ''),
    NULLIF(btrim(salesperson.coach_name), ''),
    NULLIF(btrim(coach.coach_name), '')
  INTO v_gym, v_method, v_amount, v_paid_on, v_salesperson, v_coach
  FROM public.member_memberships mm
  LEFT JOIN LATERAL (
    SELECT payment_method, amount, payment_date, gym
    FROM public.payment_success_tracker
    WHERE membership_id = mm.id
    ORDER BY created_at DESC
    LIMIT 1
  ) pst ON true
  LEFT JOIN public.staff_database salesperson ON salesperson.id = mm.salesperson_id
  LEFT JOIN public.staff_database coach
    ON coach.id = COALESCE(mm.handoff_coach_id, mm.coach_id)
  WHERE mm.id = NEW.membership_id;

  SELECT COALESCE(
    (
      SELECT NULLIF(btrim(si.last_4_digits), '')
      FROM public.stripe_invoices si
      WHERE si.membership_id = NEW.membership_id
        AND NULLIF(btrim(si.last_4_digits), '') IS NOT NULL
      ORDER BY si.payment_date DESC NULLS LAST
      LIMIT 1
    ),
    (
      SELECT NULLIF(btrim(spm.last_4_digits), '')
      FROM public.member_stripe_payment_methods spm
      WHERE spm.member_id = NEW.member_id
        AND spm.is_default IS TRUE
        AND NULLIF(btrim(spm.last_4_digits), '') IS NOT NULL
      LIMIT 1
    ),
    (
      SELECT NULLIF(btrim(mcc.last_4_digits), '')
      FROM public.member_credit_card mcc
      WHERE mcc.member_id = NEW.member_id
        AND NULLIF(btrim(mcc.last_4_digits), '') IS NOT NULL
      LIMIT 1
    ),
    (
      SELECT NULLIF(btrim(mpm.last_4_digits), '')
      FROM public.member_payment_method mpm
      WHERE mpm.member_id = NEW.member_id
        AND NULLIF(btrim(mpm.last_4_digits), '') IS NOT NULL
      LIMIT 1
    )
  )
  INTO v_last4;

  SELECT COALESCE(
    (
      SELECT COALESCE(NULLIF(btrim(si.billing_name), ''), NULLIF(btrim(si.customer_name), ''))
      FROM public.stripe_invoices si
      WHERE si.membership_id = NEW.membership_id
        AND COALESCE(NULLIF(btrim(si.billing_name), ''), NULLIF(btrim(si.customer_name), '')) IS NOT NULL
      ORDER BY si.payment_date DESC NULLS LAST
      LIMIT 1
    ),
    (
      SELECT NULLIF(btrim(sc.billing_name), '')
      FROM public.stripe_customers sc
      WHERE sc.member_id = NEW.member_id
        AND NULLIF(btrim(sc.billing_name), '') IS NOT NULL
      ORDER BY sc.updated_at DESC NULLS LAST
      LIMIT 1
    )
  )
  INTO v_payer;

  v_method_label := CASE
    WHEN v_method ILIKE 'ACH%' OR v_method ILIKE '%BECS%' THEN 'ACH'
    WHEN v_method ILIKE 'Invoice%' THEN 'invoice'
    WHEN v_method ILIKE '%card%'
      OR v_method ILIKE '%CC%'
      OR v_method ILIKE 'Square%'
      OR v_method ILIKE 'Virtual Terminal%' THEN 'card'
    ELSE COALESCE(v_method, 'not on file')
  END;

  IF v_amount IS NULL AND v_paid_on IS NULL THEN
    v_amount_line := 'not on file';
  ELSE
    v_amount_line := trim(both ' ' FROM concat_ws(
      ' ',
      CASE WHEN v_amount IS NULL THEN NULL ELSE '$' || to_char(v_amount, 'FM999999990.00') END,
      CASE WHEN v_paid_on IS NULL THEN NULL ELSE 'on ' || v_paid_on END
    ));
  END IF;

  v_notes := NULLIF(btrim(COALESCE(NEW.reactivation_notes, '')), '');

  v_block := concat_ws(
    E'\n',
    'Gym: ' || COALESCE(v_gym, 'not on file'),
    'Payment method: ' || v_method_label,
    'Card last 4: ' || COALESCE(v_last4, 'not on file'),
    'Amount paid: ' || v_amount_line,
    CASE
      WHEN v_notes ~* 'refund[[:space:]]*:' THEN NULL
      ELSE 'Refund: not stated'
    END,
    CASE
      WHEN v_notes ~* 'paying entity[[:space:]]*:' THEN NULL
      ELSE 'Paying entity: ' || COALESCE(v_payer, 'not on file')
    END,
    'Salesperson: ' || COALESCE(v_salesperson, 'not on file'),
    'Coach: ' || COALESCE(v_coach, 'not on file')
  );

  IF v_notes IS NOT NULL THEN
    v_notes := v_notes || E'\n\n' || v_block;
  ELSE
    v_notes := v_block;
  END IF;

  PERFORM private.notify_client_exit_n8n(
    'no_sale',
    NEW.membership_id,
    NEW.logged_by_staff_id,
    v_notes
  );

  RETURN NEW;
END;
$$;
