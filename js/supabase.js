import { createClient } from '@supabase/supabase-js';
import { config, isSupabaseConfigured } from './config.js';

export const supabase = isSupabaseConfigured()
  ? createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    })
  : null;
