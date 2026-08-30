import { getAdminDb, requireRole } from './db.js';
import { GooglePlacesProvider } from '../providers/google-places.js';
import { processDiscoveredProspects } from './prospecting-pipeline.js';

const discovery = new GooglePlacesProvider();

export async function runDiscoverySearch({ searchId, userId }) {
  const db = getAdminDb();
  requireRole({ id: userId });

  const { data: search, error } = await db
    .from('prospecting_searches')
    .select('*')
    .eq('id', searchId)
    .eq('created_by', userId)
    .single();

  if (error || !search) throw new Error('Prospecting search not found');

  await db.from('prospecting_searches').update({ status: 'running' }).eq('id', searchId);
  const result = await discovery.search({
    query: search.query,
    pageSize: 20,
    regionCode: 'MA'
  });

  if (result.error) {
    await db.from('prospecting_searches').update({ status: 'failed', metadata: { error: result.error } }).eq('id', searchId);
    throw new Error(result.error);
  }

  const candidates = (result.places || []).map(place => ({
    search_id: searchId,
    company_name: place.displayName?.text || 'Unknown company',
    website_url: place.websiteUri || null,
    contact_phone: place.nationalPhoneNumber || null,
    source: 'google_places',
    source_url: place.googleMapsUri || null,
    score: typeof place.rating === 'number' ? place.rating * 20 : null,
    analysis: { types: place.types || [], address: place.formattedAddress || null, rating: place.rating ?? null },
    status: 'new'
  }));

  if (candidates.length) {
    const { error: insertError } = await db.from('prospect_candidates').insert(candidates);
    if (insertError) throw new Error('Could not save discovered prospects');
  }

  await db.from('prospecting_searches').update({
    status: 'completed',
    completed_at: new Date().toISOString(),
    metadata: { provider: 'google_places', count: candidates.length, nextPageToken: result.nextPageToken }
  }).eq('id', searchId);

  // Continue automatically: discovery -> AI analysis -> qualification -> outreach queue.
  try {
    await processDiscoveredProspects({ searchId, userId });
  } catch (pipelineError) {
    await db.from('prospecting_searches').update({
      metadata: {
        provider: 'google_places',
        count: candidates.length,
        nextPageToken: result.nextPageToken,
        pipelineError: pipelineError.message
      }
    }).eq('id', searchId);
  }

  return { searchId, candidatesCount: candidates.length, candidates };
}
