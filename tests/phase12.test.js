import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

const prospecting = read('server/core/prospecting-agent.js');
const discovery = read('server/core/discovery-agent.js');
const pipeline = read('server/core/prospecting-pipeline.js');
const analysis = read('server/core/lead-analysis.js');
const outreach = read('server/core/outreach-agent.js');
const openai = read('server/providers/openai.js');

assert.match(prospecting, /assertSearchOwner/);
assert.match(prospecting, /assertLeadAccess/);
assert.match(prospecting, /assertTaskAccess/);
assert.match(prospecting, /ownedLeads/);
assert.match(prospecting, /task\.lead_id/);
assert.match(discovery, /eq\('created_by', userId\)/);
assert.match(pipeline, /processDiscoveredProspects/);
assert.match(pipeline, /score >= 60/);
assert.match(analysis, /result\?\.text \?\? result\?\.content/);
assert.match(outreach, /result\?\.text \?\? result\?\.content/);
assert.match(openai, /generate\(context\)/);
assert.match(openai, /output_text/);

// The prospecting flow must never send outreach automatically: it creates a human-approval task.
assert.match(outreach, /status: 'waiting_approval'/);
assert.match(outreach, /requires_human: true/);

// Service start must be gated through approval before creating billable work.
assert.match(prospecting, /task\.status !== 'waiting_approval'/);
assert.match(prospecting, /start_service/);

console.log('Phase 12 tests passed: discovery ownership, prospect analysis/provider contract, qualification pipeline, human-approved outreach, and task access controls.');
