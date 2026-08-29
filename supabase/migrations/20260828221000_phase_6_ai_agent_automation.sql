-- AI Agency CRM — Phase 6: AI Agent & Automation Engine
-- Apply after Phase 5. Provider-neutral, deterministic-safe architecture.

CREATE TABLE IF NOT EXISTS public.ai_agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 160),
  status text NOT NULL DEFAULT 'disabled' CHECK (status IN ('active','paused','disabled')),
  enabled boolean NOT NULL DEFAULT false,
  default_mode text NOT NULL DEFAULT 'assisted' CHECK (default_mode IN ('manual','ai_draft','assisted','automation_ready')),
  confidence_threshold integer NOT NULL DEFAULT 70 CHECK (confidence_threshold BETWEEN 0 AND 100),
  handoff_threshold integer NOT NULL DEFAULT 45 CHECK (handoff_threshold BETWEEN 0 AND 100),
  assigned_channels jsonb NOT NULL DEFAULT '[]'::jsonb,
  assigned_campaigns jsonb NOT NULL DEFAULT '[]'::jsonb,
  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS agent_name text NOT NULL DEFAULT 'Sales Agent';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS default_mode text NOT NULL DEFAULT 'assisted';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS confidence_threshold integer NOT NULL DEFAULT 70;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS handoff_threshold integer NOT NULL DEFAULT 45;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS default_language text NOT NULL DEFAULT 'fr';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS allowed_actions jsonb NOT NULL DEFAULT '["qualify_lead","create_followup","create_activity","request_human","recommend_service"]'::jsonb;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS max_automated_actions integer NOT NULL DEFAULT 0;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS approval_required boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS public.ai_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id uuid REFERENCES public.ai_agents(id) ON DELETE SET NULL,
  lead_id uuid REFERENCES public.leads(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  input_context_ref jsonb NOT NULL DEFAULT '{}'::jsonb,
  context_ref jsonb NOT NULL DEFAULT '{}'::jsonb,
  decision text NOT NULL CHECK (char_length(trim(decision)) BETWEEN 1 AND 100),
  confidence integer NOT NULL CHECK (confidence BETWEEN 0 AND 100),
  reason text NOT NULL,
  action text NOT NULL CHECK (action IN ('qualify_lead','reply','create_followup','update_lead','change_status','request_human','recommend_service','create_activity','do_nothing')),
  approval_status text NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending','approved','rejected','executed')),
  mode text NOT NULL DEFAULT 'assisted' CHECK (mode IN ('manual','ai_draft','assisted','automation_ready')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ai_decisions_parent_check CHECK (lead_id IS NOT NULL OR conversation_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.ai_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id uuid REFERENCES public.ai_agents(id) ON DELETE SET NULL,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  lead_id uuid REFERENCES public.leads(id) ON DELETE CASCADE,
  incoming_message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  draft_body text NOT NULL CHECK (char_length(trim(draft_body)) > 0),
  reasoning_summary text,
  confidence integer NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 100),
  approval_status text NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending','approved','rejected','executed')),
  mode text NOT NULL DEFAULT 'ai_draft' CHECK (mode IN ('manual','ai_draft','assisted','automation_ready')),
  approved_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at timestamptz,
  rejected_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 200),
  description text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','paused','archived')),
  mode text NOT NULL DEFAULT 'assisted' CHECK (mode IN ('manual','ai_draft','assisted','automation_ready')),
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_triggers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  trigger_type text NOT NULL CHECK (trigger_type IN ('lead_created','lead_status_changed','new_message','new_conversation','followup_due','website_preview_ready','website_approved','payment_received','deal_created','human_handoff','campaign_completed')),
  position integer NOT NULL DEFAULT 0 CHECK (position >= 0),
  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_conditions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  field text NOT NULL CHECK (char_length(trim(field)) BETWEEN 1 AND 120),
  operator text NOT NULL CHECK (operator IN ('equals','not_equals','greater_than','less_than','contains','is_empty','is_not_empty')),
  value text,
  position integer NOT NULL DEFAULT 0 CHECK (position >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  action_type text NOT NULL CHECK (action_type IN ('update_lead','create_activity','create_followup','create_notification','change_conversation_status','assign_conversation','add_tag','recommend_service','generate_response_draft','request_human','update_campaign_state')),
  position integer NOT NULL DEFAULT 0 CHECK (position >= 0),
  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  trigger_type text NOT NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','completed','failed','cancelled')),
  started_at timestamptz,
  ended_at timestamptz,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  error text,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  lead_id uuid REFERENCES public.leads(id) ON DELETE SET NULL,
  company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_execution_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id uuid NOT NULL REFERENCES public.workflow_executions(id) ON DELETE CASCADE,
  action_id uuid REFERENCES public.workflow_actions(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','completed','failed','cancelled')),
  started_at timestamptz,
  ended_at timestamptz,
  input jsonb NOT NULL DEFAULT '{}'::jsonb,
  output jsonb NOT NULL DEFAULT '{}'::jsonb,
  error text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ai_knowledge_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(trim(title)) BETWEEN 1 AND 200),
  category text NOT NULL CHECK (category IN ('company','service','pricing','website_project','faq','message_template','crm_history')),
  content text NOT NULL CHECK (char_length(trim(content)) > 0),
  source_type text NOT NULL DEFAULT 'manual',
  active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_agents_status_idx ON public.ai_agents(status,enabled);
CREATE INDEX IF NOT EXISTS ai_decisions_lead_idx ON public.ai_decisions(lead_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ai_decisions_conversation_idx ON public.ai_decisions(conversation_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ai_decisions_pending_idx ON public.ai_decisions(approval_status,created_at DESC) WHERE approval_status='pending';
CREATE INDEX IF NOT EXISTS ai_drafts_conversation_idx ON public.ai_drafts(conversation_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ai_drafts_pending_idx ON public.ai_drafts(approval_status,created_at DESC) WHERE approval_status='pending';
CREATE INDEX IF NOT EXISTS workflows_status_idx ON public.workflows(status,updated_at DESC);
CREATE INDEX IF NOT EXISTS workflow_triggers_workflow_idx ON public.workflow_triggers(workflow_id,position);
CREATE INDEX IF NOT EXISTS workflow_conditions_workflow_idx ON public.workflow_conditions(workflow_id,position);
CREATE INDEX IF NOT EXISTS workflow_actions_workflow_idx ON public.workflow_actions(workflow_id,position);
CREATE INDEX IF NOT EXISTS workflow_executions_workflow_idx ON public.workflow_executions(workflow_id,started_at DESC);
CREATE INDEX IF NOT EXISTS workflow_executions_context_idx ON public.workflow_executions(lead_id,company_id,conversation_id);
CREATE INDEX IF NOT EXISTS workflow_execution_steps_execution_idx ON public.workflow_execution_steps(execution_id,created_at);
CREATE INDEX IF NOT EXISTS ai_knowledge_active_idx ON public.ai_knowledge_items(category,active,updated_at DESC);

DROP TRIGGER IF EXISTS ai_agents_set_updated_at ON public.ai_agents;
CREATE TRIGGER ai_agents_set_updated_at BEFORE UPDATE ON public.ai_agents FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS ai_settings_set_updated_at ON public.ai_settings;
CREATE TRIGGER ai_settings_set_updated_at BEFORE UPDATE ON public.ai_settings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS ai_drafts_set_updated_at ON public.ai_drafts;
CREATE TRIGGER ai_drafts_set_updated_at BEFORE UPDATE ON public.ai_drafts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS workflows_set_updated_at ON public.workflows;
CREATE TRIGGER workflows_set_updated_at BEFORE UPDATE ON public.workflows FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS ai_knowledge_items_set_updated_at ON public.ai_knowledge_items;
CREATE TRIGGER ai_knowledge_items_set_updated_at BEFORE UPDATE ON public.ai_knowledge_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.ai_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_triggers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_execution_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_knowledge_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_agents_select ON public.ai_agents;
CREATE POLICY ai_agents_select ON public.ai_agents FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager') OR created_by=auth.uid());
DROP POLICY IF EXISTS ai_agents_manage ON public.ai_agents;
CREATE POLICY ai_agents_manage ON public.ai_agents FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));

DROP POLICY IF EXISTS ai_settings_access ON public.ai_settings;
CREATE POLICY ai_settings_access ON public.ai_settings FOR ALL TO authenticated USING (user_id=auth.uid() OR public.current_user_role() IN ('admin','manager')) WITH CHECK (user_id=auth.uid() OR public.current_user_role() IN ('admin','manager'));

DROP POLICY IF EXISTS ai_decisions_select ON public.ai_decisions;
CREATE POLICY ai_decisions_select ON public.ai_decisions FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager') OR lead_id IN (SELECT id FROM public.leads WHERE owner_id=auth.uid()));
DROP POLICY IF EXISTS ai_decisions_insert ON public.ai_decisions;
CREATE POLICY ai_decisions_insert ON public.ai_decisions FOR INSERT TO authenticated WITH CHECK (public.current_user_role() IN ('admin','manager','sales'));
DROP POLICY IF EXISTS ai_decisions_update ON public.ai_decisions;
CREATE POLICY ai_decisions_update ON public.ai_decisions FOR UPDATE TO authenticated USING (public.current_user_role() IN ('admin','manager') OR lead_id IN (SELECT id FROM public.leads WHERE owner_id=auth.uid())) WITH CHECK (public.current_user_role() IN ('admin','manager') OR lead_id IN (SELECT id FROM public.leads WHERE owner_id=auth.uid()));

DROP POLICY IF EXISTS ai_drafts_select ON public.ai_drafts;
CREATE POLICY ai_drafts_select ON public.ai_drafts FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager') OR lead_id IN (SELECT id FROM public.leads WHERE owner_id=auth.uid()));
DROP POLICY IF EXISTS ai_drafts_manage ON public.ai_drafts;
CREATE POLICY ai_drafts_manage ON public.ai_drafts FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager','sales')) WITH CHECK (public.current_user_role() IN ('admin','manager','sales'));

DROP POLICY IF EXISTS workflows_select ON public.workflows;
CREATE POLICY workflows_select ON public.workflows FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager','sales'));
DROP POLICY IF EXISTS workflows_manage ON public.workflows;
CREATE POLICY workflows_manage ON public.workflows FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));

DROP POLICY IF EXISTS workflow_triggers_access ON public.workflow_triggers;
CREATE POLICY workflow_triggers_access ON public.workflow_triggers FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_conditions_access ON public.workflow_conditions;
CREATE POLICY workflow_conditions_access ON public.workflow_conditions FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_actions_access ON public.workflow_actions;
CREATE POLICY workflow_actions_access ON public.workflow_actions FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_executions_select ON public.workflow_executions;
CREATE POLICY workflow_executions_select ON public.workflow_executions FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager','sales'));
DROP POLICY IF EXISTS workflow_executions_insert ON public.workflow_executions;
CREATE POLICY workflow_executions_insert ON public.workflow_executions FOR INSERT TO authenticated WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_executions_update ON public.workflow_executions;
CREATE POLICY workflow_executions_update ON public.workflow_executions FOR UPDATE TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_execution_steps_access ON public.workflow_execution_steps;
CREATE POLICY workflow_execution_steps_access ON public.workflow_execution_steps FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));

DROP POLICY IF EXISTS ai_knowledge_select ON public.ai_knowledge_items;
CREATE POLICY ai_knowledge_select ON public.ai_knowledge_items FOR SELECT TO authenticated USING (active=true OR public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS ai_knowledge_manage ON public.ai_knowledge_items;
CREATE POLICY ai_knowledge_manage ON public.ai_knowledge_items FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));

-- Explicitly deny any provider secret storage through the Phase 6 model: configuration is non-secret CRM configuration only.
COMMENT ON COLUMN public.ai_agents.configuration IS 'Non-secret agent configuration only. Provider API keys, OAuth secrets and private tokens must remain server-side.';
COMMENT ON COLUMN public.ai_settings.allowed_actions IS 'JSON array of internal safe actions; external provider actions are not supported in Phase 6.';
