import { supabase } from './supabase.js';

const LEGACY_KEY = 'ai_agency_leads';

export function getLegacyLeads() {
  try {
    const raw = localStorage.getItem(LEGACY_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function clearLegacyLeads() {
  localStorage.removeItem(LEGACY_KEY);
}

/**
 * Imports the old temporary lead list into Supabase.
 * This utility is deliberately opt-in and never becomes a second source of truth.
 */
export async function importLegacyLeads({ clearAfterSuccess = false } = {}) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const legacyLeads = getLegacyLeads();
  if (!legacyLeads.length) return { imported: 0, skipped: 0 };

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) throw new Error('You must be authenticated to import leads.');

  let imported = 0;
  let skipped = 0;
  for (const item of legacyLeads) {
    const companyName = String(item.companyName || item.company || item.businessName || item.name || '').trim();
    const leadName = String(item.leadName || item.contactName || item.name || companyName).trim();
    if (!companyName || !leadName) { skipped += 1; continue; }

    const city = item.city || null;
    const country = item.country || null;
    let { data: company, error: companyError } = await supabase
      .from('companies')
      .select('id')
      .ilike('name', companyName)
      .eq('city', city)
      .eq('country', country)
      .maybeSingle();
    if (companyError) throw companyError;
    if (!company) {
      const result = await supabase.from('companies').insert({
        name: companyName, city, country, website: item.website || null, phone: item.phone || null, source: item.source || 'legacy-localStorage'
      }).select('id').single();
      company = result.data;
      companyError = result.error;
      if (companyError) throw companyError;
    }

    const { error: leadError } = await supabase.from('leads').insert({
      company_id: company.id,
      name: leadName,
      status: item.status || 'new',
      score: Math.max(0, Math.min(100, Number(item.score) || 0)),
      priority: ['high','medium','low'].includes(item.priority) ? item.priority : 'medium',
      source: item.source || 'legacy-localStorage',
      recommended_service: item.recommended_service || item.recommendedService || null,
      notes: item.notes || null,
      owner_id: userData.user.id
    });
    if (leadError) throw leadError;
    imported += 1;
  }

  if (clearAfterSuccess) clearLegacyLeads();
  return { imported, skipped };
}
