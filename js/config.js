const env = import.meta.env;

export const config = Object.freeze({
  supabaseUrl: env.VITE_SUPABASE_URL || '',
  supabaseAnonKey: env.VITE_SUPABASE_ANON_KEY || '',
  appName: 'AI Agency CRM',
  environment: env.MODE || 'development'
});

export const isSupabaseConfigured = () => Boolean(config.supabaseUrl && config.supabaseAnonKey);
