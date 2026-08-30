import express from 'express';
import { supabase } from '../supabase.js';

const router = express.Router();

router.post('/search', async (req, res) => {
  try {
    const { query, target_city = null, target_industry = null } = req.body || {};
    if (!query || typeof query !== 'string') {
      return res.status(400).json({ error: 'query is required' });
    }

    const { data, error } = await supabase
      .from('prospecting_searches')
      .insert({ query: query.trim(), target_city, target_industry, status: 'pending' })
      .select()
      .single();

    if (error) return res.status(500).json({ error: error.message });
    return res.status(201).json({ search: data, next: 'discovery_provider_required' });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
});

router.post('/candidates', async (req, res) => {
  try {
    const { search_id, candidates } = req.body || {};
    if (!search_id || !Array.isArray(candidates)) {
      return res.status(400).json({ error: 'search_id and candidates[] are required' });
    }

    const rows = candidates
      .filter(c => c && c.company_name)
      .map(c => ({
        search_id,
        company_name: String(c.company_name).trim(),
        website_url: c.website_url || null,
        contact_phone: c.contact_phone || null,
        source: c.source || null,
        source_url: c.source_url || null,
        score: Number.isFinite(Number(c.score)) ? Number(c.score) : null,
        analysis: c.analysis && typeof c.analysis === 'object' ? c.analysis : {},
        status: c.analysis ? 'analyzed' : 'new'
      }));

    const { data, error } = await supabase.from('prospect_candidates').insert(rows).select();
    if (error) return res.status(500).json({ error: error.message });

    await supabase.from('prospecting_searches').update({ status: 'completed', completed_at: new Date().toISOString() }).eq('id', search_id);
    return res.status(201).json({ candidates: data });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
});

router.post('/tasks', async (req, res) => {
  try {
    const { lead_id, task_type, payload = {}, requires_human = false } = req.body || {};
    if (!lead_id || !task_type) return res.status(400).json({ error: 'lead_id and task_type are required' });

    const { data, error } = await supabase.from('sales_agent_tasks').insert({
      lead_id,
      task_type,
      payload,
      requires_human,
      status: requires_human ? 'waiting_approval' : 'pending'
    }).select().single();

    if (error) return res.status(500).json({ error: error.message });
    return res.status(201).json({ task: data });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
});

export default router;
