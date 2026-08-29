import crypto from 'node:crypto';
export function safeError(error, fallback='Integration operation failed.') { return {code:error?.code||'INTEGRATION_ERROR',message:fallback,retryable:Boolean(error?.retryable)}; }
export function verifyHmacSignature(payload, signature, secret, algorithm='sha256') {
  if(!secret || !signature) return false;
  const expected=crypto.createHmac(algorithm,secret).update(payload).digest('hex');
  const a=Buffer.from(expected); const b=Buffer.from(String(signature).replace(/^sha256=/,''));
  return a.length===b.length && crypto.timingSafeEqual(a,b);
}
export function backoffMs(attempt, base=1000, cap=60000) { return Math.min(cap, base * (2 ** Math.max(0, attempt-1))); }
export function redactSecrets(value) {
  if(value===null||value===undefined)return value;
  if(Array.isArray(value))return value.map(redactSecrets);
  if(typeof value!=='object')return value;
  const out={}; for(const [k,v] of Object.entries(value)) out[k] = /key|token|secret|password|authorization|cookie/i.test(k)?'[REDACTED]':redactSecrets(v); return out;
}
