# AI Agency CRM

## Final Version — Phase 1 → Phase 11

AI Agency CRM is a cumulative agency operating system built phase-by-phase without replacing the underlying architecture. The final project connects the operational flow from prospecting and qualification through AI-assisted sales, outreach, deals, payments, website/QR production, client review and secure delivery.

```text
Company
  ↓
Lead → Qualification → AI → Outreach → Conversation → Human Handoff → Follow-up
  ↓
Deal → Payment → Service → Website / QR Project → Production → Preview → Approval
  ↓
Required Payment → Delivery Authorization → Secure Download → Delivery Completed
```

## Stack

- HTML / CSS / modular browser JavaScript
- Vite
- Supabase Auth
- Supabase PostgreSQL + Row Level Security
- Supabase Storage foundation
- Node.js secure server layer for privileged provider operations
- Provider abstraction for AI, Email, WhatsApp, SMS and Storage
- Local QR generation (SVG / PNG)

## Architecture

```text
Browser
  ├── Supabase public client → authenticated CRM reads/writes protected by RLS
  └── Secure server API → provider operations / privileged integrations
                              ↓
                         Provider abstractions
                              ↓
                     OpenAI / Resend when configured

Supabase PostgreSQL
  ├── CRM entities
  ├── AI / workflows
  ├── outreach / conversations
  ├── website / QR production
  ├── payments / invoices / delivery
  ├── provider events
  └── activities / notifications / audit metadata
```

Sensitive provider credentials never belong in frontend code, `VITE_*`, localStorage, URLs or Git.

## Main Modules

- Dashboard — final operational metrics backed by Supabase.
- Discovery — company signals using the existing Lead Intelligence engine.
- Companies — CRM company records.
- Leads — qualification, scoring, status and intelligence.
- Outreach — campaigns, templates, messages and follow-ups.
- Conversations — inbox, messages and human handoff.
- AI Agent — AI decisions, drafts, confidence and deterministic-safe fallback.
- AI Settings / AI Knowledge — AI configuration and structured knowledge.
- Workflows — conditions, guarded actions, idempotency and execution logs.
- Deals — commercial opportunities and services.
- Payments — payment lifecycle, milestones and deal balances.
- Invoices — invoice foundation and line items.
- Delivery — secure website / QR delivery gates and download tracking.
- Websites — information builder, templates, generation, preview, approval and revisions.
- QR Codes — Google Review QR projects, Classic / Modern / Premium templates and local SVG/PNG generation.
- Services — reusable service catalog used by deals and projects.
- Integrations — provider configuration/status and server-side connection tests.
- Settings — profile and operational configuration overview.

## AI

Phase 8 introduced real server-side AI provider support while preserving the Phase 6 deterministic-safe engine.

- OpenAI is called only from `server/`.
- Structured CRM analysis is validated before decisions are persisted or acted upon.
- AI drafts remain traceable in `ai_drafts` and require approval according to the configured mode.
- Confidence thresholds and Human Handoff remain active.
- AI usage is recorded in `ai_usage_logs` when available.
- Provider-unavailable operation falls back to the deterministic-safe engine; an unavailable provider is never presented as connected.

## Outreach / Email

The provider-neutral email abstraction can execute email server-side when credentials are configured.

Lifecycle:

```text
Draft → Queued → Sent → Delivered → Opened → Replied
                         ↘ Failed / Bounced / Cancelled
```

Idempotency keys, provider events, webhook signature validation, rate limits and retry metadata are used to avoid duplicate sends and unsafe webhook processing.

## Website Production

Website Projects use the existing Phase 4 foundation and Phase 9 production engine.

Lifecycle:

```text
Draft → Information Required → Generating → Preview Ready
      → Client Review → Revision Requested → Approved
      → Payment Pending → Ready for Delivery → Delivered → Completed
```

Available templates include:

- Site Vitrine Modern
- Professional Corporate

The renderer remains template-based and extensible. Client previews use expiring tokens and expose rendered preview content rather than internal CRM records.

## Website Delivery Gate

Final packaging/download is controlled by the database gate:

```text
Production Ready
      +
Client Approval
      +
Required Payment
      ↓
Delivery Authorized
      ↓
Secure Download
      ↓
Delivery Completed
```

The project records final ZIP size, SHA-256, generation time, delivery status and download events.

## QR Production

QR Projects support:

- validated destination URLs;
- Company / Lead / Deal / Service relations;
- Classic / Modern / Premium templates;
- local QR matrix generation;
- SVG and PNG output;
- preview;
- duplicate / archive;
- download tracking;
- payment/delivery gating when a paid Deal is attached.

No external QR SaaS or API key is required.

## Payments & Billing

Payment states:

```text
pending → authorized → paid
                    ↘ failed / cancelled
paid → refunded
```

Payment milestones support deposit, remaining balance and full payment. Deal payment summaries calculate paid amount, outstanding balance and percentage paid from database records.

Invoice foundation supports:

- invoice number;
- company / lead / deal;
- line items;
- subtotal;
- discount;
- tax;
- total;
- currency;
- issue / due dates;
- lifecycle status.

No external payment processor or billing provider is required by the final project.

## Security

The final project applies security at multiple layers:

- Supabase RLS on CRM and operational tables.
- Ownership checks through Lead / Deal relationships.
- Server-side provider credentials.
- Finance-authorized payment and invoice status transitions.
- Secure delivery authorization RPCs.
- Expiring website preview tokens.
- Webhook signature verification and idempotency.
- Rate limits and retry limits.
- No API keys in frontend code, localStorage, URLs or Git.
- Safe error responses and secret redaction in provider infrastructure.

Phase 11 specifically tightened financial status transitions so normal sales users cannot self-authorize a payment as paid/refunded/authorized or change invoice lifecycle status.

## Environment Variables

### Browser-safe

```env
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```

### Server-only

```env
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
OPENAI_API_KEY=
OPENAI_MODEL=gpt-5.6-luna
EMAIL_PROVIDER_SECRET=
EMAIL_FROM=
WHATSAPP_TOKEN=
SMS_PROVIDER_SECRET=
WEBHOOK_SECRET=
PORT=8787
INTEGRATION_MAX_RETRIES=3
AI_TIMEOUT_MS=30000
EMAIL_TIMEOUT_MS=30000
AI_MAX_REQUESTS_PER_MINUTE=30
EMAIL_MAX_REQUESTS_PER_MINUTE=20
MAX_AUTOMATED_ACTIONS=20
```

The example file contains placeholders only. Never commit real credentials.

## Database

Migrations are cumulative and must be applied in timestamp order from Phase 2 through Phase 11.

Phase migrations:

- `20260828170000_phase_2_crm_foundation.sql`
- `20260828183000_phase_3_core_crm.sql`
- `20260828210000_phase_4_website_production.sql`
- `20260828215900_phase_5_enum_extensions.sql`
- `20260828220000_phase_5_communication_outreach.sql`
- `20260828221000_phase_6_ai_agent_automation.sql`
- `20260828223000_phase_7_secure_integrations.sql`
- `20260828230000_phase_8_real_integrations.sql`
- `20260828240000_phase_9_website_qr_production.sql`
- `20260828250000_phase_10_payments_billing_delivery.sql`
- `20260828260000_phase_11_final_audit.sql`

`supabase/schema.sql` is kept synchronized with the cumulative database definition.

## Local Development

1. Copy `.env.example` to `.env.local`.
2. Configure `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for the browser.
3. Apply the Supabase migrations in order.
4. Configure server-only credentials only when the corresponding provider is actually available.
5. Install dependencies:

```bash
npm install
```

6. Run the frontend:

```bash
npm run dev
```

7. Run the secure server separately when required:

```bash
npm run server
```

## Testing

Available commands:

```bash
npm run check
npm test
npm run test:phase8
npm run test:phase9
npm run test:phase10
npm run test:phase11
npm run build
```

The phase tests include deterministic/static checks for provider security, QR generation, payment calculations, delivery gates, database structures and final integration references.

A real Supabase RLS/migration test, external AI call, real email send, webhook from a public provider and production deployment are only considered successful when executed against a configured environment.

## Production Readiness Notes

The repository is structured for a real installation, but repository-level verification cannot substitute for deployment verification. Before production activation, configure Supabase, apply migrations, verify RLS with real users/roles, configure provider credentials in the server environment, execute provider connection tests, and run an authenticated browser smoke test.

The current repository does not contain real provider credentials.

## Git History

The project keeps the cumulative phase history. Phase 11 is a final integration/audit hardening phase rather than a replacement architecture.

Final phase commit:

```text
feat: finalize ai agency crm production readiness
```

## Final Scope

**AI Agency CRM — Final Version — Phase 1 → Phase 11**

No Phase 12 is part of this project.
