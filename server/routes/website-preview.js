import { generateWebsitePreview, getWebsitePreview, reviewWebsitePreview } from '../core/website-generator.js';
import { requireRole } from '../core/db.js';

export async function handleWebsitePreview({ path, method, body, user, url, res }) {
  if (path === '/api/website/preview' && method === 'POST') {
    requireRole(user);
    if (!body?.projectId) return { status: 400, body: { error: 'projectId is required' } };
    try {
      const result = await generateWebsitePreview({ projectId: body.projectId, userId: user.id });
      return { status: 200, body: result };
    } catch (e) {
      return { status: e.status || 502, body: { error: e.message, code: e.code || 'WEBSITE_GENERATION_ERROR' } };
    }
  }

  if (path === '/api/website/preview/review' && method === 'POST') {
    if (!body?.projectId || !body?.token || !body?.decision) return { status: 400, body: { error: 'projectId, token and decision are required' } };
    try {
      const result = await reviewWebsitePreview({ projectId: body.projectId, token: body.token, decision: body.decision, message: body.message });
      return { status: 200, body: result };
    } catch (e) {
      const message = e.message || 'Preview review failed';
      const status = /token|expired|not found/i.test(message) ? 404 : 400;
      return { status, body: { error: message, code: 'PREVIEW_REVIEW_ERROR' } };
    }
  }

  if (path.startsWith('/preview/') && method === 'GET') {
    const projectId = path.split('/')[2];
    if (!projectId) return { status: 404, body: { error: 'Preview not found' } };
    const token = new URL(url || '', 'http://localhost').searchParams.get('token');
    try {
      const html = await getWebsitePreview({ projectId, token });
      res.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'private, no-store',
        'x-content-type-options': 'nosniff',
        'content-security-policy': "default-src 'self' https: data:; script-src 'unsafe-inline' https:; style-src 'unsafe-inline' https:; img-src 'self' https: data:;"
      });
      res.end(html);
      return { handled: true };
    } catch (e) {
      return { status: 404, body: { error: 'Preview unavailable' } };
    }
  }
  return null;
}
