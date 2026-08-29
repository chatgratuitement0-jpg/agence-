export class ProviderError extends Error {
  constructor(message, { provider='unknown', operation='unknown', code='PROVIDER_ERROR', retryable=false, cause=null } = {}) {
    super(message); this.name='ProviderError'; this.provider=provider; this.operation=operation; this.code=code; this.retryable=retryable; this.cause=cause;
  }
}
export class Provider { constructor(name){ this.name=name; } async health(){ return {status:'not_configured',provider:this.name}; } }
export class EmailProvider extends Provider { constructor(name='email'){super(name)} async send(){throw new ProviderError('Email provider is not configured.',{provider:this.name,operation:'send',code:'NOT_CONFIGURED'});} async reply(){throw new ProviderError('Email provider is not configured.',{provider:this.name,operation:'reply',code:'NOT_CONFIGURED'});} }
export class AIProvider extends Provider { constructor(name='ai'){super(name)} async generate(){throw new ProviderError('AI provider is not configured.',{provider:this.name,operation:'generate',code:'NOT_CONFIGURED'});} async analyze(){throw new ProviderError('AI provider is not configured.',{provider:this.name,operation:'analyze',code:'NOT_CONFIGURED'});} }
export class WhatsAppProvider extends Provider { constructor(name='whatsapp'){super(name)} async send(){throw new ProviderError('WhatsApp provider is not configured.',{provider:this.name,operation:'send',code:'NOT_CONFIGURED'});} }
export class SMSProvider extends Provider { constructor(name='sms'){super(name)} async send(){throw new ProviderError('SMS provider is not configured.',{provider:this.name,operation:'send',code:'NOT_CONFIGURED'});} }
export class StorageProvider extends Provider { constructor(name='storage'){super(name)} async put(){throw new ProviderError('Storage provider is not configured.',{provider:this.name,operation:'put',code:'NOT_CONFIGURED'});} }
