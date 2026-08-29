import assert from 'node:assert/strict';
import fs from 'node:fs';
import QRCode from '../js/vendor/qrcode/index.js';
import QRErrorCorrectLevel from '../js/vendor/qrcode/QRErrorCorrectLevel.js';

const url='https://example.com/google-review-test?id=phase9';
const qr=new QRCode(-1,QRErrorCorrectLevel.L);qr.addData(url);qr.make();
assert.ok(qr.getModuleCount()>=21,'QR matrix should be generated');
assert.equal(qr.modules.length,qr.getModuleCount());
assert.ok(qr.modules.every(row=>row.length===qr.getModuleCount()),'QR matrix must be square');
assert.ok(qr.modules.flat().some(Boolean),'QR matrix must contain dark modules');

const required=['js/website-generator.js','js/website-projects.js','js/qr-generator.js','js/qr-projects.js','js/deals.js','js/preview.js','supabase/migrations/20260828240000_phase_9_website_qr_production.sql'];
for(const file of required)assert.ok(fs.existsSync(file),`${file} must exist`);
const migration=fs.readFileSync('supabase/migrations/20260828240000_phase_9_website_qr_production.sql','utf8');
assert.match(migration,/website_revision_requests/);
assert.match(migration,/website_preview_views/);
assert.match(migration,/client_review_website_preview/);
assert.match(migration,/qr_templates/);
assert.match(migration,/qr_projects/);
assert.match(migration,/enable row level security/i);
assert.doesNotMatch(fs.readFileSync('.env.example','utf8'),/VITE_.*(OPENAI|EMAIL|WEBHOOK|SERVICE_ROLE)/i);
console.log('Phase 9 static + QR engine tests passed.');
