import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {paymentTotals,invoiceTotal,deliveryGate,safePaymentAmount} from '../js/payment-utils.js';

const t=paymentTotals(2500,[{amount:500,status:'paid'},{amount:250,status:'pending'},{amount:100,status:'failed'}]);
assert.equal(t.total,2500); assert.equal(t.paid,500); assert.equal(t.pending,250); assert.equal(t.outstanding,2000); assert.equal(t.percent,20); assert.equal(t.status,'partial');
assert.deepEqual(paymentTotals(0,[]),{total:0,paid:0,pending:0,outstanding:0,percent:100,status:'not_required'});
assert.equal(invoiceTotal(2500,200,100),2400); assert.equal(invoiceTotal(100,150,0),0);
assert.equal(deliveryGate({type:'Website',approved:false,dealValue:2500,paidAmount:2500,productionStatus:'ready_for_delivery'}).allowed,false);
assert.equal(deliveryGate({type:'Website',approved:true,dealValue:2500,paidAmount:1000,productionStatus:'ready_for_delivery'}).reason,'Waiting for final payment');
assert.equal(deliveryGate({type:'Website',approved:true,dealValue:2500,paidAmount:2500,productionStatus:'preview_ready'}).reason,'Website not ready');
assert.equal(deliveryGate({type:'Website',approved:true,dealValue:2500,paidAmount:2500,productionStatus:'packaged'}).allowed,true);
assert.equal(deliveryGate({type:'QR',approved:true,dealValue:0,paidAmount:0,productionStatus:'active'}).allowed,true);
assert.equal(safePaymentAmount('500',1000),500);
assert.throws(()=>safePaymentAmount('0',1000),/greater than zero/);
assert.throws(()=>safePaymentAmount('1200',1000),/exceeds/);

const sql=readFileSync(new URL('../supabase/migrations/20260828250000_phase_10_payments_billing_delivery.sql',import.meta.url),'utf8');
for(const table of ['payment_milestones','invoices','invoice_items','deliveries','delivery_events']) assert.equal((sql.match(new RegExp(`create table if not exists public\\.${table}`,'g'))||[]).length,1,`duplicate ${table} definition`);
assert.match(sql,/alter table public\.payments alter column status type text/);
assert.match(sql,/create policy deliveries_access/); assert.match(sql,/create policy invoices_access/);
assert.match(sql,/create or replace function public\.set_payment_status/); assert.match(sql,/create or replace function public\.authorize_delivery_download/);
assert.match(sql,/create or replace function public\.set_invoice_status/); assert.doesNotMatch(sql,/sk-[A-Za-z0-9]{20,}/);
console.log('Phase 10 tests passed: payment calculations, invoice totals, delivery gates, SQL structure and security guards.');
