import { supabase } from './supabase.js';

export const authConfigured = () => Boolean(supabase);
const unavailable = () => ({ data: null, error: new Error('Supabase is not configured.') });

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function explainAuthError(error) {
  if (!error) return null;

  const code = error.code || error.name || '';
  const status = error.status || '';
  const rawMessage = String(error.message || '').trim();

  if (code === 'invalid_credentials' || /invalid login credentials/i.test(rawMessage)) {
    return new Error(`Email ou mot de passe incorrect. (Supabase: ${code || 'invalid_credentials'})`);
  }

  if (code === 'email_not_confirmed' || /email not confirmed/i.test(rawMessage)) {
    return new Error('Cette adresse email n’est pas encore confirmée. Vérifie ta boîte mail Supabase.');
  }

  if (code === 'user_not_found') {
    return new Error('Aucun compte Supabase ne correspond à cette adresse email.');
  }

  if (status === 429 || code === 'over_request_rate_limit') {
    return new Error('Trop de tentatives de connexion. Attends quelques minutes puis réessaie.');
  }

  const details = [code && `code=${code}`, status && `status=${status}`].filter(Boolean).join(', ');
  return new Error(rawMessage || `Échec de connexion${details ? ` (${details})` : ''}.`);
}

export async function signIn(email, password) {
  if (!supabase) return unavailable();

  const cleanEmail = normalizeEmail(email);
  const result = await supabase.auth.signInWithPassword({
    email: cleanEmail,
    password: String(password || '')
  });

  if (result.error) {
    return {
      ...result,
      error: explainAuthError(result.error)
    };
  }

  return result;
}

export async function signUp(email, password, fullName = '') {
  if (!supabase) return unavailable();

  return supabase.auth.signUp({
    email: normalizeEmail(email),
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
  const { data, error } = await supabase.auth.getUser();
  if (error || !data?.user) return null;
  return data.user;
}

export async function getCurrentProfile() {
  if (!supabase) return { data: { profile: null }, error: new Error('Supabase is not configured.') };

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return {
      data: { profile: null },
      error: userError || new Error('No authenticated user.')
    };
  }

  const result = await supabase
    .from('profiles')
    .select('id,email,full_name,avatar_url,role,created_at,updated_at')
    .eq('id', userData.user.id)
    .single();

  return { data: { profile: result.data }, error: result.error };
}

export function onAuthStateChange(callback) {
  if (!supabase) return { data: { subscription: { unsubscribe() {} } } };
  return supabase.auth.onAuthStateChange(callback);
}
