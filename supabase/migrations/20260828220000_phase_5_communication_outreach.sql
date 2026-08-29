-- AI Agency CRM — Phase 5: Communication, outreach & conversation workflows
-- Apply after Phase 4. Extends existing enums/tables; no duplicate CRM systems.


-- Reusable outbound message templates.
CREATE TABLE IF NOT EXISTS public.message_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 160),
  channel public.outreach_channel NOT NULL DEFAULT 'email',
  subject text,
  body text NOT NULL CHECK (char_length(trim(body)) > 0),
  service_id uuid REFERENCES public.services(id) ON DELETE SET NULL,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.outreach_campaign_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.outreach_campaigns(id) ON DELETE CASCADE,
  lead_id uuid REFERENCES public.leads(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT campaign_target_parent_check CHECK (lead_id IS NOT NULL OR company_id IS NOT NULL),
  CONSTRAINT campaign_target_unique_lead UNIQUE (campaign_id, lead_id),
  CONSTRAINT campaign_target_unique_company UNIQUE (campaign_id, company_id)
);

ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS template_id uuid REFERENCES public.message_templates(id) ON DELETE SET NULL;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS service_id uuid REFERENCES public.services(id) ON DELETE SET NULL;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS scheduled_at timestamptz;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS started_at timestamptz;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS completed_at timestamptz;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.outreach_messages ALTER COLUMN lead_id DROP NOT NULL;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS template_id uuid REFERENCES public.message_templates(id) ON DELETE SET NULL;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS subject text;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS queued_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS failed_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS bounced_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS provider text;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS provider_message_id text;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS error_message text;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.conversations ALTER COLUMN status SET DEFAULT 'open';
UPDATE public.conversations SET status='open' WHERE status='active';
UPDATE public.conversations SET status='handoff' WHERE status='human_required';
UPDATE public.outreach_campaigns SET status='running' WHERE status='active';
UPDATE public.outreach_messages SET status='queued',queued_at=coalesce(queued_at,now()) WHERE status='pending';
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS last_message_preview text;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS unread_count integer NOT NULL DEFAULT 0 CHECK (unread_count >= 0);
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS last_activity_at timestamptz;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS subject text;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS ai_handling boolean NOT NULL DEFAULT false;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS status public.outreach_message_status DEFAULT 'sent';
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS failed_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS bounced_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS attachments jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS provider text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS provider_message_id text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS error_message text;

CREATE TABLE IF NOT EXISTS public.conversation_handoffs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (reason IN ('client_requested_human','pricing_negotiation','complex_request','complaint','high_value_lead','ai_confidence_too_low')),
  requested_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_to uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'needs_human' CHECK (status IN ('needs_human','human_handling','resolved')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  resolved_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.follow_ups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid REFERENCES public.leads(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  campaign_id uuid REFERENCES public.outreach_campaigns(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(trim(title)) BETWEEN 1 AND 200),
  due_at timestamptz NOT NULL,
  priority public.priority_level NOT NULL DEFAULT 'medium',
  assigned_to uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed','cancelled')),
  notes text,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT follow_up_parent_check CHECK (lead_id IS NOT NULL OR company_id IS NOT NULL OR conversation_id IS NOT NULL OR campaign_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS message_templates_channel_idx ON public.message_templates(channel) WHERE archived_at IS NULL;
CREATE INDEX IF NOT EXISTS campaign_targets_campaign_idx ON public.outreach_campaign_targets(campaign_id);
CREATE INDEX IF NOT EXISTS campaign_targets_lead_idx ON public.outreach_campaign_targets(lead_id);
CREATE INDEX IF NOT EXISTS campaign_targets_company_idx ON public.outreach_campaign_targets(company_id);
CREATE INDEX IF NOT EXISTS outreach_campaigns_status_idx ON public.outreach_campaigns(status);
CREATE INDEX IF NOT EXISTS outreach_campaigns_scheduled_idx ON public.outreach_campaigns(scheduled_at);
CREATE INDEX IF NOT EXISTS outreach_messages_campaign_idx ON public.outreach_messages(campaign_id);
CREATE INDEX IF NOT EXISTS outreach_messages_status_idx ON public.outreach_messages(status);
CREATE INDEX IF NOT EXISTS outreach_messages_lead_idx ON public.outreach_messages(lead_id);
CREATE INDEX IF NOT EXISTS conversations_assigned_idx ON public.conversations(assigned_to,status);
CREATE INDEX IF NOT EXISTS conversations_activity_idx ON public.conversations(last_activity_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS conversation_handoffs_conversation_idx ON public.conversation_handoffs(conversation_id,created_at DESC);
CREATE INDEX IF NOT EXISTS follow_ups_due_idx ON public.follow_ups(due_at) WHERE status='pending';
CREATE INDEX IF NOT EXISTS follow_ups_assigned_idx ON public.follow_ups(assigned_to,status,due_at);

DROP TRIGGER IF EXISTS message_templates_set_updated_at ON public.message_templates;
CREATE TRIGGER message_templates_set_updated_at BEFORE UPDATE ON public.message_templates FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS outreach_campaigns_set_updated_at ON public.outreach_campaigns;
CREATE TRIGGER outreach_campaigns_set_updated_at BEFORE UPDATE ON public.outreach_campaigns FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS follow_ups_set_updated_at ON public.follow_ups;
CREATE TRIGGER follow_ups_set_updated_at BEFORE UPDATE ON public.follow_ups FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS conversations_set_updated_at_phase5 ON public.conversations;
CREATE TRIGGER conversations_set_updated_at_phase5 BEFORE UPDATE ON public.conversations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.message_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outreach_campaign_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_handoffs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follow_ups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_templates_access ON public.message_templates;
CREATE POLICY message_templates_access ON public.message_templates FOR ALL TO authenticated
USING (public.current_user_role() IN ('admin','manager') OR created_by=auth.uid())
WITH CHECK (public.current_user_role() IN ('admin','manager') OR created_by=auth.uid());

DROP POLICY IF EXISTS campaign_targets_access ON public.outreach_campaign_targets;
CREATE POLICY campaign_targets_access ON public.outreach_campaign_targets FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.outreach_campaigns c WHERE c.id=campaign_id AND c.created_by=auth.uid())
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=lead_id AND l.owner_id=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.outreach_campaigns c WHERE c.id=campaign_id AND c.created_by=auth.uid())
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=lead_id AND l.owner_id=auth.uid())
);

DROP POLICY IF EXISTS outreach_messages_access ON public.outreach_messages;
CREATE POLICY outreach_messages_access ON public.outreach_messages FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=outreach_messages.lead_id AND l.owner_id=auth.uid())
  OR EXISTS (SELECT 1 FROM public.outreach_campaigns c WHERE c.id=outreach_messages.campaign_id AND c.created_by=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=outreach_messages.lead_id AND l.owner_id=auth.uid())
  OR EXISTS (SELECT 1 FROM public.outreach_campaigns c WHERE c.id=outreach_messages.campaign_id AND c.created_by=auth.uid())
);

DROP POLICY IF EXISTS conversations_access ON public.conversations;
CREATE POLICY conversations_access ON public.conversations FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager') OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=conversations.lead_id AND l.owner_id=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager') OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=conversations.lead_id AND l.owner_id=auth.uid())
);

DROP POLICY IF EXISTS messages_access ON public.messages;
CREATE POLICY messages_access ON public.messages FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=messages.conversation_id AND (c.assigned_to=auth.uid() OR l.owner_id=auth.uid()))
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=messages.conversation_id AND (c.assigned_to=auth.uid() OR l.owner_id=auth.uid()))
);

DROP POLICY IF EXISTS conversation_handoffs_access ON public.conversation_handoffs;
CREATE POLICY conversation_handoffs_access ON public.conversation_handoffs FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager')
  OR requested_by=auth.uid() OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=conversation_id AND l.owner_id=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager')
  OR requested_by=auth.uid() OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=conversation_id AND l.owner_id=auth.uid())
);

DROP POLICY IF EXISTS follow_ups_access ON public.follow_ups;
CREATE POLICY follow_ups_access ON public.follow_ups FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager') OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=follow_ups.lead_id AND l.owner_id=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager') OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=follow_ups.lead_id AND l.owner_id=auth.uid())
);


ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS source_type text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS source_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS notifications_source_unique_idx ON public.notifications(user_id,type,source_id) WHERE source_id IS NOT NULL;
-- Keep conversation denormalized activity/unread fields synchronized when messages arrive.
CREATE OR REPLACE FUNCTION public.sync_conversation_from_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.conversations
  SET last_message_at=NEW.created_at,
      last_message_preview=left(NEW.message,240),
      last_activity_at=NEW.created_at,
      unread_count=CASE WHEN NEW.sender_type='lead' THEN unread_count+1 ELSE unread_count END
  WHERE id=NEW.conversation_id;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS messages_sync_conversation ON public.messages;
CREATE TRIGGER messages_sync_conversation AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.sync_conversation_from_message();

-- A real database-side notification for inbound replies.
CREATE OR REPLACE FUNCTION public.notify_inbound_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user uuid; v_lead uuid; v_company uuid;
BEGIN
  IF NEW.sender_type='lead' THEN
    SELECT c.assigned_to,c.lead_id INTO v_user,v_lead FROM public.conversations c WHERE c.id=NEW.conversation_id;
    SELECT l.company_id INTO v_company FROM public.leads l WHERE l.id=v_lead;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
      VALUES(v_user,'new_reply','New reply','A lead replied in a CRM conversation.',v_lead,v_company,'message',NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS messages_notify_inbound ON public.messages;
CREATE TRIGGER messages_notify_inbound AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.notify_inbound_message();

CREATE OR REPLACE FUNCTION public.notify_handoff()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_lead uuid; v_company uuid;
BEGIN
  SELECT c.lead_id,l.company_id INTO v_lead,v_company FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=NEW.conversation_id;
  IF NEW.assigned_to IS NOT NULL THEN
    INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
    VALUES(NEW.assigned_to,'human_handoff','Human handoff required','A conversation requires human attention.',v_lead,v_company,'handoff',NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS conversation_handoffs_notify ON public.conversation_handoffs;
CREATE TRIGGER conversation_handoffs_notify AFTER INSERT ON public.conversation_handoffs FOR EACH ROW EXECUTE FUNCTION public.notify_handoff();

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_conversation_id uuid)
RETURNS public.conversations LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.conversations;
BEGIN
  UPDATE public.conversations c SET unread_count=0 WHERE c.id=p_conversation_id AND (
    public.current_user_role() IN ('admin','manager') OR c.assigned_to=auth.uid()
    OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=c.lead_id AND l.owner_id=auth.uid())
  );
  IF NOT FOUND THEN RAISE EXCEPTION 'Conversation not found or not authorized.' USING errcode='42501'; END IF;
  SELECT * INTO v FROM public.conversations WHERE id=p_conversation_id; RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_conversation_read(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_conversation_message(p_conversation_id uuid,p_message text,p_sender_type public.sender_type default 'human',p_channel public.conversation_channel default 'email',p_ai_generated boolean default false)
RETURNS public.messages LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.messages;
BEGIN
  IF p_message IS NULL OR char_length(trim(p_message))=0 THEN RAISE EXCEPTION 'Message cannot be empty.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.conversations c WHERE c.id=p_conversation_id AND (public.current_user_role() IN ('admin','manager') OR c.assigned_to=auth.uid() OR EXISTS(SELECT 1 FROM public.leads l WHERE l.id=c.lead_id AND l.owner_id=auth.uid()))) THEN
    RAISE EXCEPTION 'Not authorized to write to this conversation.' USING errcode='42501';
  END IF;
  INSERT INTO public.messages(conversation_id,sender_type,sender_id,message,channel,ai_generated,status) VALUES(p_conversation_id,p_sender_type,CASE WHEN p_sender_type='human' THEN auth.uid() ELSE NULL END,p_message,p_channel,p_ai_generated,CASE WHEN p_sender_type='human' THEN 'queued'::public.outreach_message_status ELSE 'sent'::public.outreach_message_status END) RETURNING * INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.create_conversation_message(uuid,text,public.sender_type,public.conversation_channel,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.create_conversation_message(uuid,text,public.sender_type,public.conversation_channel,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_follow_up(p_follow_up_id uuid)
RETURNS public.follow_ups LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.follow_ups;
BEGIN
  UPDATE public.follow_ups f SET status='completed',completed_at=now()
  WHERE f.id=p_follow_up_id AND (public.current_user_role() IN ('admin','manager') OR f.assigned_to=auth.uid() OR EXISTS(SELECT 1 FROM public.leads l WHERE l.id=f.lead_id AND l.owner_id=auth.uid()));
  IF NOT FOUND THEN RAISE EXCEPTION 'Follow-up not found or not authorized.' USING errcode='42501'; END IF;
  SELECT * INTO v FROM public.follow_ups WHERE id=p_follow_up_id; RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_follow_up(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.complete_follow_up(uuid) TO authenticated;


-- Provider-independent failure/completion notifications.
CREATE OR REPLACE FUNCTION public.notify_outreach_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user uuid; v_lead uuid; v_company uuid;
BEGIN
  IF TG_TABLE_NAME='outreach_messages' AND NEW.status IN ('failed','bounced') AND COALESCE(OLD.status::text,'') IS DISTINCT FROM NEW.status::text THEN
    SELECT c.created_by INTO v_user FROM public.outreach_campaigns c WHERE c.id=NEW.campaign_id;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
      VALUES(v_user,'email_failed','Email failed','An outreach message failed or bounced.',NEW.lead_id,NEW.company_id,'outreach_message',NEW.id)
      ON CONFLICT DO NOTHING;
    END IF;
  ELSIF TG_TABLE_NAME='outreach_campaigns' AND NEW.status='completed' AND COALESCE(OLD.status::text,'') IS DISTINCT FROM 'completed' THEN
    v_user:=NEW.created_by;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,source_type,source_id)
      VALUES(v_user,'campaign_completed','Campaign completed','An outreach campaign was marked completed.','campaign',NEW.id)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS outreach_messages_notify_events ON public.outreach_messages;
CREATE TRIGGER outreach_messages_notify_events AFTER UPDATE OF status ON public.outreach_messages FOR EACH ROW EXECUTE FUNCTION public.notify_outreach_events();
DROP TRIGGER IF EXISTS outreach_campaigns_notify_events ON public.outreach_campaigns;
CREATE TRIGGER outreach_campaigns_notify_events AFTER UPDATE OF status ON public.outreach_campaigns FOR EACH ROW EXECUTE FUNCTION public.notify_outreach_events();

CREATE OR REPLACE FUNCTION public.notify_operational_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user uuid; v_lead uuid; v_company uuid;
BEGIN
  IF TG_TABLE_NAME='website_projects' AND NEW.client_approved_at IS NOT NULL AND OLD.client_approved_at IS NULL THEN
    SELECT owner_id,company_id INTO v_user,v_company FROM public.leads WHERE id=NEW.lead_id;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id) VALUES(v_user,'website_approval','Website approved','A client approved a website project.',NEW.lead_id,v_company,'website_project',NEW.id) ON CONFLICT DO NOTHING;
    END IF;
  ELSIF TG_TABLE_NAME='payments' AND NEW.status='paid' AND COALESCE(OLD.status::text,'') IS DISTINCT FROM 'paid' THEN
    SELECT l.owner_id,l.company_id INTO v_user,v_company FROM public.deals d JOIN public.leads l ON l.id=d.lead_id WHERE d.id=NEW.deal_id;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id) SELECT v_user,'payment_event','Payment event','A payment was recorded as paid.',d.lead_id,v_company,'payment',NEW.id FROM public.deals d WHERE d.id=NEW.deal_id ON CONFLICT DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS website_projects_notify_events ON public.website_projects;
CREATE TRIGGER website_projects_notify_events AFTER UPDATE OF client_approved_at ON public.website_projects FOR EACH ROW EXECUTE FUNCTION public.notify_operational_events();
DROP TRIGGER IF EXISTS payments_notify_events ON public.payments;
CREATE TRIGGER payments_notify_events AFTER UPDATE OF status ON public.payments FOR EACH ROW EXECUTE FUNCTION public.notify_operational_events();

DROP TRIGGER IF EXISTS leads_notify_qualified ON public.leads;
CREATE OR REPLACE FUNCTION public.notify_qualified_lead()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.status='qualified' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.owner_id IS NOT NULL THEN
    INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
    VALUES(NEW.owner_id,'qualified_lead','New qualified lead','A lead was moved to qualified status.',NEW.id,NEW.company_id,'lead',NEW.id)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER leads_notify_qualified AFTER UPDATE OF status ON public.leads FOR EACH ROW EXECUTE FUNCTION public.notify_qualified_lead();

CREATE OR REPLACE FUNCTION public.outreach_analytics()
RETURNS json LANGUAGE sql SECURITY DEFINER SET search_path=public STABLE AS $$
  SELECT json_build_object(
    'total_campaigns',(SELECT count(*) FROM public.outreach_campaigns WHERE archived_at IS NULL),
    'messages_sent',(SELECT count(*) FROM public.outreach_messages WHERE status IN ('sent','delivered','opened','replied')),
    'delivered',(SELECT count(*) FROM public.outreach_messages WHERE status IN ('delivered','opened','replied')),
    'failed',(SELECT count(*) FROM public.outreach_messages WHERE status IN ('failed','bounced')),
    'replies',(SELECT count(*) FROM public.outreach_messages WHERE status='replied'),
    'reply_rate',CASE WHEN (SELECT count(*) FROM public.outreach_messages WHERE status IN ('sent','delivered','opened','replied'))=0 THEN 0 ELSE round(100.0*(SELECT count(*) FROM public.outreach_messages WHERE status='replied')/(SELECT count(*) FROM public.outreach_messages WHERE status IN ('sent','delivered','opened','replied')),2) END,
    'qualified_leads',(SELECT count(*) FROM public.leads WHERE status='qualified'),
    'human_handoffs',(SELECT count(*) FROM public.conversation_handoffs),
    'followups_completed',(SELECT count(*) FROM public.follow_ups WHERE status='completed')
  );
$$;
REVOKE ALL ON FUNCTION public.outreach_analytics() FROM public;
GRANT EXECUTE ON FUNCTION public.outreach_analytics() TO authenticated;

-- Notification helper for application-owned events (website/payment/campaign/etc.).
CREATE OR REPLACE FUNCTION public.create_notification(p_user_id uuid,p_type text,p_title text,p_message text default null,p_lead_id uuid default null,p_company_id uuid default null)
RETURNS public.notifications LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.notifications;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Notification user is required.'; END IF;
  IF p_user_id <> auth.uid() AND public.current_user_role() NOT IN ('admin','manager') THEN RAISE EXCEPTION 'Not authorized to create a notification.' USING errcode='42501'; END IF;
  INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id) VALUES(p_user_id,p_type,p_title,p_message,p_lead_id,p_company_id) RETURNING * INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.create_notification(uuid,text,text,text,uuid,uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.create_notification(uuid,text,text,text,uuid,uuid) TO authenticated;
