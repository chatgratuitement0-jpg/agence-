import { serverConfig } from '../core/config.js';

export class GooglePlacesProvider {
  constructor(name = 'google-places') {
    this.name = name;
  }

  async health() {
    return { ok: Boolean(serverConfig.googlePlacesApiKey), provider: this.name };
  }

  async search({ query, pageSize = 10, regionCode = 'MA' }) {
    if (!serverConfig.googlePlacesApiKey) {
      return { configured: false, places: [], error: 'Google Places API key is not configured' };
    }

    const response = await fetch('https://places.googleapis.com/v1/places:searchText', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': serverConfig.googlePlacesApiKey,
        'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.websiteUri,places.nationalPhoneNumber,places.types,places.rating,nextPageToken'
      },
      body: JSON.stringify({
        textQuery: query,
        pageSize: Math.min(Math.max(Number(pageSize) || 10, 1), 20),
        regionCode
      })
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      return { configured: true, places: [], error: payload?.error?.message || `Google Places request failed (${response.status})` };
    }

    return { configured: true, places: payload.places || [], nextPageToken: payload.nextPageToken || null };
  }
}
