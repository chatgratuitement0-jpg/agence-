-- Phase 8: real AI/email integration, usage tracking and guarded automation metadata.
ALTER TYPE public.outreach_message_status ADD VALUE IF NOT EXISTS 'queued';
ALTER TYPE public.outreach_message_status ADD VALUE IF NOT EXISTS 'bounced';
ALTER TYPE public.outreach_status ADD VALUE IF NOT EXISTS 'scheduled';
ALTER TYPE public.outreach_status ADD VALUE IF NOT EXISTS 'running';
ALTER TYPE public.outreach_status ADD VALUE IF NOT EXISTS 'sending';
ALTER TYPE public.outreach_status ADD VALUE IF NOT EXISTS 'cancelled';

CREATE TABLE IF NOT EXISTS public.ai_usage_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 provider text NOT NULL,
 model text,
 request_type text NOT NULL,
 user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 lead_id uuid REFERENCES public.leads(id) ON DELETE SET NULL,
 conversation_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL,
 agent_id uuid REFERENCES public.ai_agents(id) ON DELETE SET NULL,
 success boolean NOT NULL DEFAULT false,
 input_tokens integer NOT NULL DEFAULT 0 CHECK(input_tokens >= 0),
 output_tokens integer NOT NULL DEFAULT 0 CHECK(output_tokens >= 0),
 total_tokens integer NOT NULL DEFAULT 0 CHECK(total_tokens >= 0),
 estimated_cost numeric(12,8),
 latency_ms integer CHECK(latency_ms IS NULL OR latency_ms >= 0),
 error_code text,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ai_usage_logs_created_idx ON public.ai_usage_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS ai_usage_logs_lead_idx ON public.ai_usage_logs(lead_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ai_usage_logs_conversation_idx ON public.ai_usage_logs(conversation_id,created_at DESC);

ALTER TABLE public.workflow_executions ADD COLUMN IF NOT EXISTS idempotency_key text;
ALTER TABLE public.workflow_executions ADD COLUMN IF NOT EXISTS retry_count integer NOT NULL DEFAULT 0 CHECK(retry_count >= 0);
ALTER TABLE public.workflow_executions ADD COLUMN IF NOT EXISTS max_actions integer NOT NULL DEFAULT 20 CHECK(max_actions >= 0);
ALTER TABLE public.workflow_executions ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE UNIQUE INDEX IF NOT EXISTS workflow_executions_idempotency_idx ON public.workflow_executions(workflow_id,idempotency_key) WHERE idempotency_key IS NOT NULL;

ALTER TABLE public.workflow_execution_steps ADD COLUMN IF NOT EXISTS retry_count integer NOT NULL DEFAULT 0 CHECK(retry_count >= 0);
ALTER TABLE public.workflow_execution_steps ADD COLUMN IF NOT EXISTS idempotency_key text;
CREATE UNIQUE INDEX IF NOT EXISTS workflow_execution_steps_idempotency_idx ON public.workflow_execution_steps(execution_id,idempotency_key) WHERE idempotency_key IS NOT NULL;

ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS idempotency_key text;
CREATE UNIQUE INDEX IF NOT EXISTS outreach_messages_idempotency_idx ON public.outreach_messages(idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.provider_connection_tests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 integration_id uuid REFERENCES public.integrations(id) ON DELETE CASCADE,
 provider text NOT NULL,
 status text NOT NULL CHECK(status IN ('success','failed','not_configured')),
 error_code text,
 safe_error_message text,
 latency_ms integer,
 created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS provider_connection_tests_provider_idx ON public.provider_connection_tests(provider,created_at DESC);

ALTER TABLE public.ai_usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_connection_tests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ai_usage_select ON public.ai_usage_logs;
CREATE POLICY ai_usage_select ON public.ai_usage_logs FOR SELECT TO authenticated USING(public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS provider_connection_tests_select ON public.provider_connection_tests;
CREATE POLICY provider_connection_tests_select ON public.provider_connection_tests FOR SELECT TO authenticated USING(public.current_user_role() IN ('admin','manager') OR created_by=auth.uid());

COMMENT ON TABLE public.ai_usage_logs IS 'Server-written AI usage telemetry. Never store provider secrets or prompts containing credentials.';
COMMENT ON TABLE public.provider_connection_tests IS 'Server-side provider connection test results; credentials are never stored here.';
