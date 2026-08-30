import express from 'express';
import { getAdminDb } from '../core/db.js';
import { handleIncomingSalesMessage } from '../core/whatsapp-agent.js';

const router = express.Router();

router.get('/', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token && token === process.env.WHATSAPP_VERIFY_TOKEN) {
    return res.status(200).send(challenge);
  }
  return res.sendStatus(403);
});

router.post('/', express.json(), async (req, res) => {
  // Acknowledge Meta quickly; processing continues asynchronously.
  res.sendStatus(200);

  try {
    const entry = req.body?.entry || [];
    const changes = entry.flatMap(item => item?.changes || []);

    for (const change of changes) {
      const value = change?.value;
      const messages = value?.messages || [];
      for (const incoming of messages) {
        if (incoming?.type !== 'text') continue;
        const phone = incoming?.from;
        const text = incoming?.text?.body;
        if (!phone || !text) continue;

        const db = getAdminDb();
        const { data: lead } = await db
          .from('leads')
          .select('id,owner_id,phone')
          .eq('phone', phone)
          .maybeSingle();

        if (!lead) continue;
        await handleIncomingSalesMessage({ leadId: lead.id, message: text, userId: lead.owner_id });
      }
    }
  } catch (error) {
    console.error('WhatsApp webhook processing failed:', error);
  }
});

export default router;
