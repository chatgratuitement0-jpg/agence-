import { getAdminDb } from './db.js';
import { GooglePlacesProvider } from '../providers/google-places.js';

const discovery = new GooglePlacesProvider();

const TEST_PROSPECTS = [
  { company_name: 'Atlas Café Rabat', website_url: null, contact_phone: null, score: 82, analysis: { priority: 'hot', recommended_service: 'Google Review QR Code', address: 'Rabat, Morocco', test_mode: true } },
  { company_name: 'Rabat Garden Restaurant', website_url: null, contact_phone: null, score: 74, analysis: { priority: 'warm', recommended_service: 'Vitrine Website', address: 'Rabat, Morocco', test_mode: true } },
  { company_name: 'Ocean View Café', website_url: null, contact_phone: null, score: 68, analysis: { priority: 'warm', recommended_service: 'Professional Website', address: 'Rabat, Morocco', test_mode: true } },
  { company_name: 'Medina Food House', website_url: null, contact_phone: null, score: 61, analysis: { priority: 'warm', recommended_service: 'Vitrine Website', address: 'Rabat, Morocco', test_mode: true } },
  { company_name: 'Rabat Lounge', website_url: null, contact_phone: null, score: 55, analysis: { priority: 'low', recommended_service: 'Google Review QR Code', address: 'Rabat, Morocco', test_mode: true } }
];

export async function runDiscoverySearch({ searchId, userId }) {
  const db = getAdminDb();

  const { data: search, error } = await db
    .from('prospecting_searches')
    .select('*')
    .eq('id', searchId)
    .eq('created_by', userId)
    .single();

  if (error || !search) throw new Error('Prospecting search not found');

  await db.from('prospecting_searches')
    .update({ status: 'running' })
    .eq('id', searchId)
    .eq('created_by', userId);

  let candidates;
  let metadata;

  const result = await discovery.search({
    query: search.query,
    pageSize: 20,
    regionCode: 'MA'
  });

  if (result.error) {
    candidates = TEST_PROSPECTS.map(candidate => ({
      search_id: searchId,
      company_name: candidate.company_name,
      website_url: candidate.website_url,
      contact_phone: candidate.contact_phone,
      source: 'internal_test',
      source_url: null,
      score: candidate.score,
      analysis: candidate.analysis,
      status: 'new'
    }));
    metadata = {
      mode: 'internal_test',
      provider: 'internal_test_fallback',
      reason: result.error,
      count: candidates.length
    };
  } else {
    candidates = (result.places || []).map(place => ({
      search_id: searchId,
      company_name: place.displayName?.text || 'Unknown company',
      website_url: place.websiteUri || null,
      contact_phone: place.nationalPhoneNumber || null,
      source: 'google_places',
      source_url: place.googleMapsUri || null,
      score: typeof place.rating === 'number' ? place.rating * 20 : null,
      analysis: {
        types: place.types || [],
        address: place.formattedAddress || null,
        rating: place.rating ?? null
      },
      status: 'new'
    }));
    metadata = {
      mode: 'live',
      provider: 'google_places',
      count: candidates.length,
      nextPageToken: result.nextPageToken || null
    };
  }

  if (candidates.length) {
    const { error: insertError } = await db
      .from('prospect_candidates')
      .insert(candidates);
    if (insertError) throw new Error(`Could not save discovered prospects: ${insertError.message}`);
  }

  const { error: completeError } = await db.from('prospecting_searches').update({
    status: 'completed',
    completed_at: new Date().toISOString(),
    metadata
  }).eq('id', searchId).eq('created_by', userId);

  if (completeError) throw new Error(`Could not complete prospecting search: ${completeError.message}`);

  return { searchId, candidatesCount: candidates.length, candidates, mode: metadata.mode };
}
