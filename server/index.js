import http from 'node:http';
import {serverConfig,isServerConfigured} from './core/config.js';
import {handleWebhook} from './routes/webhooks.js';
import {handleApi} from './routes/api.js';
import {getRequestUser} from './core/db.js';
import {integrationLimiters} from './core/rate-limit.js';
import {createProviders} from './providers/index.js';
const providers=createProviders();
const json=(res,status,body)=>{res.writeHead(status,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(body));};
const readBody=req=>new Promise((resolve,reject)=>{let s='';req.on('data',c=>{s+=c;if(s.length>2_000_000){req.destroy();reject(new Error('Payload too large'));}});req.on('end',()=>resolve(s));req.on('error',reject);});
const server=http.createServer(async(req,res)=>{try{
  if(req.method==='GET'&&req.url==='/health'){return json(res,200,{ok:true,service:'secure-server-layer',configured:isServerConfigured(),providers:{ai:await providers.ai.health(),email:await providers.email.health(),whatsapp:await providers.whatsapp.health(),sms:await providers.sms.health()}})}
  if(req.url?.startsWith('/webhooks/')){if(!integrationLimiters.webhook.allow(req.socket.remoteAddress||'unknown'))return json(res,429,{error:'Webhook rate limit exceeded'});const provider=req.url.split('/')[2];const raw=await readBody(req);const result=await handleWebhook({provider,eventType:req.headers['x-event-type']||'unknown',rawBody:raw,signature:req.headers['x-webhook-signature'],secret:serverConfig.webhookSecret,svixId:req.headers['svix-id'],svixTimestamp:req.headers['svix-timestamp'],svixSignature:req.headers['svix-signature']});return json(res,result.status,result.body)}
  if(req.url?.startsWith('/api/')){const user=await getRequestUser(req.headers.authorization);let body={};if(req.method!=='GET'){const raw=await readBody(req);try{body=JSON.parse(raw||'{}')}catch{return json(res,400,{error:'Invalid JSON payload'})}}const result=await handleApi({path:req.url.split('?')[0],req,body,user});return json(res,result.status,result.body)}
  return json(res,404,{error:'Not found'});
}catch(e){console.error('server error',e.message);return json(res,500,{error:'Internal server error'})}});
if(process.env.START_SERVER==='true')server.listen(serverConfig.port,'127.0.0.1',()=>console.log(`Secure server layer listening on 127.0.0.1:${serverConfig.port}`));
export {server};
