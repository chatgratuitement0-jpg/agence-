import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {paymentTotals,invoiceTotal,safePaymentAmount} from '../js/payment-utils.js';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const migrations=fs.readdirSync(path.join(root,'supabase/migrations')).filter(x=>x.endsWith('.sql')).sort();
const allSql=migrations.map(f=>read(`supabase/migrations/${f}`)).join('\n');

assert.deepEqual(paymentTotals(1000,[{amount:250,status:'paid'},{amount:100,status:'pending'}]),{total:1000,paid:250,pending:100,outstanding:750,percent:25,status:'partial'});
assert.equal(invoiceTotal(1000,100,180),1080);
assert.equal(safePaymentAmount(250,1000),250);
assert.throws(()=>safePaymentAmount(1001,1000));

const requiredTables=['companies','leads','conversations','deals','payments','invoices','invoice_items','deliveries','website_projects','qr_projects','ai_agents','ai_decisions','ai_drafts','workflows','workflow_executions','notifications'];
for(const table of requiredTables) assert.match(allSql,new RegExp(`create table(?: if not exists)? public\\.${table}\\b`,'i'),`missing table: ${table}`);
for(const fn of ['set_payment_status','set_invoice_status','get_delivery_gate','authorize_delivery_download','record_delivery_download','complete_delivery']) assert.match(allSql,new RegExp(`create or replace function public\\.${fn}\\b`,'i'),`missing function: ${fn}`);
for(const table of ['payments','invoices','deliveries','website_projects','qr_projects']) assert.match(allSql,new RegExp(`alter table public\\.${table} enable row level security`,'i'),`missing RLS: ${table}`);
assert.match(read('supabase/migrations/20260828260000_phase_11_final_audit.sql'),/Only admin or manager can change a payment financial status/);
assert.match(read('supabase/migrations/20260828260000_phase_11_final_audit.sql'),/Only admin or manager can change invoice status/);
assert.match(read('js/app.js'),/Conversations:'conversations'/);
assert.match(read('js/app.js'),/Deals:'deals'/);
assert.match(read('js/app.js'),/Invoices:'payments'/);
assert.match(read('js/dashboard.js'),/totalCompanies/);
assert.match(read('js/dashboard.js'),/pendingFollowUps/);
assert.match(read('js/dashboard.js'),/pendingAiApprovals/);
assert.match(read('js/dashboard.js'),/humanHandoffs/);
assert.doesNotMatch(read('js/ai-agent.js'),/deterministic simulation/i);
assert.doesNotMatch(read('js/ai-settings.js'),/not connected.*external.*unavailable/i);
for(const file of fs.readdirSync(path.join(root,'js')).filter(x=>x.endsWith('.js'))){assert.doesNotMatch(read(`js/${file}`),/sk-[A-Za-z0-9]{10,}|BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY/);}
assert.match(read('.env.example'),/VITE_SUPABASE_URL=/);
assert.match(read('.env.example'),/OPENAI_API_KEY=/);
assert.match(read('.env.example'),/RESEND_API_KEY=|EMAIL_PROVIDER_SECRET=/);
assert.doesNotMatch(read('.env.example'),/VITE_(?!SUPABASE_ANON_KEY$).*?(?:SECRET|TOKEN|PRIVATE|SERVICE_ROLE).*=/im);
assert.match(read('README.md'),/Phase 1 → Phase 12/);
console.log('Phase 11 tests passed: final integration references, dashboard/search coverage, payment/invoice security guards, delivery functions, RLS/static secret checks.');