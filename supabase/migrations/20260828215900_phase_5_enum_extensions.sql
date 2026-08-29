-- AI Agency CRM — Phase 5 enum extensions.
-- Kept in its own migration so new enum values are committed before columns/functions use them.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_status'::regtype AND enumlabel='scheduled') THEN ALTER TYPE public.outreach_status ADD VALUE 'scheduled'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_status'::regtype AND enumlabel='running') THEN ALTER TYPE public.outreach_status ADD VALUE 'running'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_status'::regtype AND enumlabel='cancelled') THEN ALTER TYPE public.outreach_status ADD VALUE 'cancelled'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_message_status'::regtype AND enumlabel='draft') THEN ALTER TYPE public.outreach_message_status ADD VALUE 'draft'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_message_status'::regtype AND enumlabel='queued') THEN ALTER TYPE public.outreach_message_status ADD VALUE 'queued'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_message_status'::regtype AND enumlabel='bounced') THEN ALTER TYPE public.outreach_message_status ADD VALUE 'bounced'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_message_status'::regtype AND enumlabel='cancelled') THEN ALTER TYPE public.outreach_message_status ADD VALUE 'cancelled'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_status'::regtype AND enumlabel='open') THEN ALTER TYPE public.conversation_status ADD VALUE 'open'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_status'::regtype AND enumlabel='qualified') THEN ALTER TYPE public.conversation_status ADD VALUE 'qualified'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_status'::regtype AND enumlabel='handoff') THEN ALTER TYPE public.conversation_status ADD VALUE 'handoff'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_status'::regtype AND enumlabel='archived') THEN ALTER TYPE public.conversation_status ADD VALUE 'archived'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_channel'::regtype AND enumlabel='other') THEN ALTER TYPE public.conversation_channel ADD VALUE 'other'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_channel'::regtype AND enumlabel='other') THEN ALTER TYPE public.outreach_channel ADD VALUE 'other'; END IF;
END $$;
