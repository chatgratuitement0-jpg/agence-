-- Phase 7: secure integration foundation. Secrets are intentionally NOT stored in public CRM tables.
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS connection_status text NOT NULL DEFAULT 'not_configured';
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS provider_account_label text;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_success_at timestamptz;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_error_at timestamptz;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_error_code text;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_error_message text;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_event_at timestamptz;
ALTER TABLE public.integrations ADD CONSTRAINT integrations_connection_status_check CHECK (connection_status IN ('not_configured','configured','connected','error','disabled'));
CREATE INDEX IF NOT EXISTS integrations_connection_status_idx ON public.integrations(connection_status,enabled,updated_at DESC);
DROP TRIGGER IF EXISTS integrations_set_updated_at ON public.integrations;
CREATE TRIGGER integrations_set_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.provider_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 integration_id uuid REFERENCES public.integrations(id) ON DELETE SET NULL,
 provider text NOT NULL,
 event_type text NOT NULL,
 external_event_id text,
 status text NOT NULL DEFAULT 'received' CHECK(status IN ('received','processing','processed','failed','ignored')),
 payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 normalized_event jsonb NOT NULL DEFAULT '{}'::jsonb,
 signature_verified boolean NOT NULL DEFAULT false,
 idempotency_key text,
 retry_count integer NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
 next_retry_at timestamptz,
 error_code text,
 error_message text,
 received_at timestamptz NOT NULL DEFAULT now(),
 processed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(provider,idempotency_key)
);
CREATE INDEX IF NOT EXISTS provider_events_status_idx ON public.provider_events(status,next_retry_at);
CREATE INDEX IF NOT EXISTS provider_events_provider_idx ON public.provider_events(provider,event_type,received_at DESC);

CREATE TABLE IF NOT EXISTS public.integration_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 integration_id uuid REFERENCES public.integrations(id) ON DELETE SET NULL,
 provider text NOT NULL,
 operation text NOT NULL,
 status text NOT NULL CHECK(status IN ('started','succeeded','failed','skipped')),
 error_code text,
 safe_error_message text,
 retryable boolean NOT NULL DEFAULT false,
 attempt integer NOT NULL DEFAULT 1 CHECK(attempt > 0),
 related_lead_id uuid REFERENCES public.leads(id) ON DELETE SET NULL,
 related_company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
 related_conversation_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS integration_logs_integration_idx ON public.integration_logs(integration_id,created_at DESC);
CREATE INDEX IF NOT EXISTS integration_logs_provider_idx ON public.integration_logs(provider,operation,created_at DESC);

CREATE TABLE IF NOT EXISTS public.integration_audit_log (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 integration_id uuid REFERENCES public.integrations(id) ON DELETE SET NULL,
 action text NOT NULL CHECK(action IN ('enabled','disabled','connection_attempt','provider_error','webhook_received','webhook_processed','ai_request','email_request','whatsapp_request','sms_request')),
 provider text NOT NULL,
 success boolean NOT NULL DEFAULT true,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS integration_audit_idx ON public.integration_audit_log(provider,created_at DESC);

ALTER TABLE public.provider_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS provider_events_select ON public.provider_events;
CREATE POLICY provider_events_select ON public.provider_events FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS provider_events_manage ON public.provider_events;
CREATE POLICY provider_events_manage ON public.provider_events FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS integration_logs_select ON public.integration_logs;
CREATE POLICY integration_logs_select ON public.integration_logs FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS integration_logs_insert ON public.integration_logs;
CREATE POLICY integration_logs_insert ON public.integration_logs FOR INSERT TO authenticated WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS integration_audit_select ON public.integration_audit_log;
CREATE POLICY integration_audit_select ON public.integration_audit_log FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS integration_audit_insert ON public.integration_audit_log;
CREATE POLICY integration_audit_insert ON public.integration_audit_log FOR INSERT TO authenticated WITH CHECK (public.current_user_role() IN ('admin','manager') OR user_id=auth.uid());

COMMENT ON TABLE public.integrations IS 'Non-secret provider metadata only. Provider credentials belong in a server-side secret manager/environment, never this client-readable table.';
COMMENT ON COLUMN public.integrations.configuration IS 'Non-secret configuration metadata only; never store API keys, OAuth secrets, tokens, passwords or private credentials here.';
COMMENT ON COLUMN public.provider_events.payload IS 'Validated provider payload. Secrets and authorization material must be redacted before persistence.';
