import { WhatsAppProvider as BaseWhatsAppProvider, ProviderError } from './provider.js';

const GRAPH_API_BASE = 'https://graph.facebook.com';

function required(name) {
  const value = process.env[name];
  if (!value) throw new ProviderError(`WhatsApp is not configured: missing ${name}.`, { provider: 'whatsapp', operation: 'config', code: 'NOT_CONFIGURED' });
  return value;
}

export class WhatsAppProvider extends BaseWhatsAppProvider {
  constructor(name = 'whatsapp') {
    super(name);
    this.token = process.env.WHATSAPP_ACCESS_TOKEN || '';
    this.phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID || '';
    this.graphVersion = process.env.WHATSAPP_GRAPH_VERSION || 'v23.0';
  }

  async health() {
    if (!this.token || !this.phoneNumberId) {
      return { status: 'not_configured', provider: this.name };
    }

    const response = await fetch(`${GRAPH_API_BASE}/${this.graphVersion}/${this.phoneNumberId}?fields=id,display_phone_number,verified_name`, {
      headers: { Authorization: `Bearer ${this.token}` },
    });

    if (!response.ok) {
      return { status: 'error', provider: this.name, http_status: response.status };
    }

    const data = await response.json();
    return { status: 'ok', provider: this.name, phone_number_id: data.id, display_phone_number: data.display_phone_number, verified_name: data.verified_name };
  }

  async send({ to, text, previewUrl = false }) {
    const token = required('WHATSAPP_ACCESS_TOKEN');
    const phoneNumberId = required('WHATSAPP_PHONE_NUMBER_ID');
    if (!to || !text) {
      throw new ProviderError('WhatsApp recipient and text are required.', { provider: this.name, operation: 'send', code: 'INVALID_INPUT' });
    }

    const response = await fetch(`${GRAPH_API_BASE}/${this.graphVersion}/${phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to,
        type: 'text',
        text: { preview_url: Boolean(previewUrl), body: text },
      }),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new ProviderError(data?.error?.message || 'WhatsApp message could not be sent.', {
        provider: this.name,
        operation: 'send',
        code: data?.error?.code ? String(data.error.code) : 'SEND_FAILED',
        retryable: response.status >= 500 || response.status === 429,
      });
    }

    return {
      provider: this.name,
      message_id: data?.messages?.[0]?.id || null,
      contacts: data?.contacts || [],
      raw: data,
    };
  }
}
