import assert from 'node:assert/strict';
import {OpenAIProvider} from '../server/providers/openai.js';
import {ResendEmailProvider} from '../server/providers/resend.js';
import {redactSecrets,backoffMs} from '../server/core/security.js';
import {RateLimiter} from '../server/core/rate-limit.js';

const ai=new OpenAIProvider();
const email=new ResendEmailProvider();
assert.equal((await ai.health()).status,'not_configured');
assert.equal((await email.health()).status,'not_configured');
await assert.rejects(()=>ai.analyze({message:'hello'}),e=>e.code==='NOT_CONFIGURED');
await assert.rejects(()=>email.send({to:'test@example.com',subject:'x',text:'x'}),e=>e.code==='NOT_CONFIGURED');
assert.deepEqual(redactSecrets({apiKey:'secret',nested:{token:'x'},safe:'ok'}),{apiKey:'[REDACTED]',nested:{token:'[REDACTED]'},safe:'ok'});
assert.equal(backoffMs(1),1000);assert.equal(backoffMs(20),60000);
const limiter=new RateLimiter({windowMs:1000,max:1});assert.equal(limiter.allow('a'),true);assert.equal(limiter.allow('a'),false);
console.log('Phase 8 local provider/security tests passed');
