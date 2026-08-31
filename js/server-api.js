import {getCurrentSession} from './auth.js';

export async function serverRequest(path,{method='GET',body}={}){
  const s=await getCurrentSession();
  const token=s.data?.session?.access_token;
  if(!token)throw new Error('Authentication required.');
  const r=await fetch(path,{method,headers:{'content-type':'application/json',authorization:`Bearer ${token}`},body:method==='GET'?undefined:JSON.stringify(body||{})});
  let data={};
  try{data=await r.json()}catch{}
  if(!r.ok){
    const e=new Error(data.error||`Server request failed (${r.status}).`);
    e.code=data.code;
    e.status=r.status;
    e.fallback=data.fallback||r.status>=500;
    throw e;
  }
  return data;
}

export const aiAnalyze=(body)=>serverRequest('/api/ai/analyze',{method:'POST',body});
export const aiDraft=(body)=>serverRequest('/api/ai/draft',{method:'POST',body});
export const sendEmail=(body)=>serverRequest('/api/email/send',{method:'POST',body});
export const providerHealth=()=>serverRequest('/api/providers/health');
export const testProvider=(provider)=>serverRequest('/api/providers/test',{method:'POST',body:{provider}});
