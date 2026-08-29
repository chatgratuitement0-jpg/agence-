import { createClient } from '@supabase/supabase-js';
import { serverConfig } from './config.js';

export function getAdminDb(){
  if(!serverConfig.supabaseUrl || !serverConfig.supabaseServiceRoleKey) throw new Error('Server Supabase is not configured.');
  return createClient(serverConfig.supabaseUrl,serverConfig.supabaseServiceRoleKey,{auth:{persistSession:false,autoRefreshToken:false}});
}
export async function getRequestUser(authorization){
  if(!authorization?.startsWith('Bearer ')) return null;
  const token=authorization.slice(7).trim(); if(!token) return null;
  const db=getAdminDb();
  const {data,error}=await db.auth.getUser(token);
  if(error||!data.user) return null;
  const {data:profile}=await db.from('profiles').select('id,email,full_name,role').eq('id',data.user.id).single();
  return profile ? {...profile,user:data.user} : {...data.user,role:'sales'};
}
export function requireRole(user,roles=['admin','manager','sales']){
  if(!user || !roles.includes(user.role)) { const e=new Error('Unauthorized'); e.status=401; throw e; }
  return user;
}
