export class RateLimiter {
  constructor({windowMs=60_000,max=60}={}) { this.windowMs=windowMs; this.max=max; this.buckets=new Map(); }
  allow(key){ const now=Date.now(); const b=this.buckets.get(key); if(!b||now-b.startedAt>=this.windowMs){this.buckets.set(key,{startedAt:now,count:1});return true;} if(b.count>=this.max)return false; b.count++; return true; }
  cleanup(){ const cutoff=Date.now()-this.windowMs; for(const [k,b] of this.buckets)if(b.startedAt<cutoff)this.buckets.delete(k); }
}
export const integrationLimiters=Object.freeze({ai:new RateLimiter({max:30}),email:new RateLimiter({max:20}),whatsapp:new RateLimiter({max:30}),sms:new RateLimiter({max:20}),webhook:new RateLimiter({max:120})});
