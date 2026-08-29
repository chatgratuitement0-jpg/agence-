import {EmailProvider,AIProvider,WhatsAppProvider,SMSProvider,StorageProvider} from './provider.js';
import {OpenAIProvider} from './openai.js';
import {ResendEmailProvider} from './resend.js';
export const providerRegistry=Object.freeze({email:ResendEmailProvider,ai:OpenAIProvider,whatsapp:WhatsAppProvider,sms:SMSProvider,storage:StorageProvider});
export function createProvider(kind,name){const Ctor=providerRegistry[kind];if(!Ctor)throw new Error(`Unsupported provider kind: ${kind}`);return new Ctor(name||kind);}
export function createProviders(){return {email:new ResendEmailProvider(),ai:new OpenAIProvider(),whatsapp:new WhatsAppProvider(),sms:new SMSProvider()};}
