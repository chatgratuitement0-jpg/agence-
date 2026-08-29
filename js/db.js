import { supabase } from './supabase.js';
function client(){if(!supabase) throw new Error('Supabase is not configured.'); return supabase;}
export async function query(table,{columns='*',filters={},order,page=1,pageSize=25,count=false}={}){let q=client().from(table).select(columns,count?{count:'exact'}:undefined);for(const[k,v]of Object.entries(filters))if(v!==undefined&&v!==null&&v!=='')q=q.eq(k,v);if(order)q=q.order(order.column,{ascending:order.ascending??false});const from=(page-1)*pageSize;return q.range(from,from+pageSize-1)}
export async function listRows(table,opts={}){return query(table,{...opts,page:1,pageSize:opts.limit||100,count:false})}
export async function getRow(table,id,columns='*'){return client().from(table).select(columns).eq('id',id).single()}
export async function createRow(table,payload){return client().from(table).insert(payload).select().single()}
export async function updateRow(table,id,payload){return client().from(table).update(payload).eq('id',id).select().single()}
export async function deleteRow(table,id){return client().from(table).delete().eq('id',id)}
export {client as supabaseClient};
