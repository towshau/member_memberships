-- Fire the client-exit Slack (n8n) from member_not_renewing, not only from
-- submit_client_exit_form. The no-sale skill writes this table directly.
--
-- No sale: insert with no_sale, or an update that changes no_sale,
-- reactivation_notes, confirmation_date, or estimated_return_12_months.
-- Follow-up columns do not send another Slack.
--
-- Not renewing "accounts ready to close" stays on submit_client_exit_form
-- so that path still sends one Slack and this trigger does not send a second.

CREATE OR REPLACE FUNCTION private.trg_client_exit_slack_from_not_renewing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'net'
AS $$
BEGIN
  IF NEW.membership_id IS NULL OR NOT COALESCE(NEW.no_sale, false) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT'
     OR NEW.no_sale IS DISTINCT FROM OLD.no_sale
     OR NEW.reactivation_notes IS DISTINCT FROM OLD.reactivation_notes
     OR NEW.confirmation_date IS DISTINCT FROM OLD.confirmation_date
     OR NEW.estimated_return_12_months IS DISTINCT FROM OLD.estimated_return_12_months
  THEN
    PERFORM private.notify_client_exit_n8n(
      'no_sale',
      NEW.membership_id,
      NEW.logged_by_staff_id,
      NEW.reactivation_notes
    );
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.trg_client_exit_slack_from_not_renewing() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_client_exit_slack_from_not_renewing ON public.member_not_renewing;

CREATE TRIGGER trg_client_exit_slack_from_not_renewing
AFTER INSERT OR UPDATE ON public.member_not_renewing
FOR EACH ROW
EXECUTE FUNCTION private.trg_client_exit_slack_from_not_renewing();
