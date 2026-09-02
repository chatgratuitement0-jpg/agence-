import { supabase } from './supabase.js';

export const authConfigured = () => Boolean(supabase);
const unavailable = () => ({ data: null, error: new Error('Supabase is not configured.') });

export async function signIn(email, password) {
  if (!supabase) return unavailable();
  return supabase.auth.signInWithPassword({ email, password });
}

export async function signUp(email, password, fullName = '') {
  if (!supabase) return unavailable();
  return supabase.auth.signUp({
    email,
    password,
    options: {
      data: { full_name: fullName.trim() || null }
    }
  });
}

export async function signOut() {
  if (!supabase) return { error: null };
  return supabase.auth.signOut();
}

export async function getCurrentSession() {
  if (!supabase) return { data: { session: null }, error: new Error('Supabase is not configured.') };
  return supabase.auth.getSession();
}

export async function getCurrentUser() {
  if (!supabase) return null;
  const {data,error} = await supabase.auth.getUser();
  if (error || !data?.user) return null;
  return data.user;
}

export async function getCurrentProfile() {
  if (!supabase) return { data: { profile: null }, error: new Error('Supabase is not configured.') };
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return { data: { profile: null }, error: userError || new Error('No authenticated user.') };
  const result = await supabase.from('profiles').select('id,email,full_name,avatar_url,role,created_at,updated_at').eq('id', userData.user.id).single();
  return { data: { profile: result.data }, error: result.error };
}

export function onAuthStateChange(callback) {
  if (!supabase) return { data: { subscription: { unsubscribe() {} } } };
  return supabase.auth.onAuthStateChange(callback);
}
