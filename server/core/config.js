const required = name => process.env[name] || '';
export const serverConfig = Object.freeze({
  port: Number(process.env.PORT || 8787),
  supabaseUrl: required('SUPABASE_URL'),
  supabaseServiceRoleKey: required('SUPABASE_SERVICE_ROLE_KEY'),
  openaiApiKey: required('OPENAI_API_KEY'),
  whatsappToken: required('WHATSAPP_TOKEN'),
  googlePlacesApiKey: required('GOOGLE_PLACES_API_KEY'),
  smsProviderSecret: required('SMS_PROVIDER_SECRET'),
  webhookSecret: required('WEBHOOK_SECRET'),
  maxRetries: Math.max(0, Number(process.env.INTEGRATION_MAX_RETRIES || 3)),
  openaiModel: process.env.OPENAI_MODEL || 'gpt-5.6-luna',
  aiTimeoutMs: Math.max(1000, Number(process.env.AI_TIMEOUT_MS || 30000)),
  aiMaxRequestsPerMinute: Math.max(1, Number(process.env.AI_MAX_REQUESTS_PER_MINUTE || 30)),
  maxAutomatedActions: Math.max(0, Number(process.env.MAX_AUTOMATED_ACTIONS || 20)),
});
export const isServerConfigured = () => Boolean(serverConfig.supabaseUrl && serverConfig.supabaseServiceRoleKey);