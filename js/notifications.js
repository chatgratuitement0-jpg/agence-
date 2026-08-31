import { supabaseClient } from './db.js';

export async function listNotifications({ unreadOnly = false, limit = 20 } = {}) {
  let q = supabaseClient()
    .from('notifications')
    .select('id,type,title,body,data,read_at,created_at,source_type,source_id')
    .order('created_at', { ascending: false })
    .limit(limit);

  if (unreadOnly) q = q.is('read_at', null);
  return q;
}

export async function markNotificationRead(id) {
  return supabaseClient()
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('id', id);
}
