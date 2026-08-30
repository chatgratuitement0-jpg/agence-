import { getAdminDb } from './db.js';

const BUCKET = process.env.DELIVERY_BUCKET || 'deliveries';
const SIGNED_URL_TTL = 60 * 60 * 24;

export async function uploadDeliveryPackage({ projectId, zipBuffer, fileName }) {
  const db = getAdminDb();
  const path = `${projectId}/${fileName}`;

  const { error } = await db.storage.from(BUCKET).upload(path, zipBuffer, {
    contentType: 'application/zip',
    upsert: true,
    cacheControl: '3600'
  });
  if (error) throw new Error(`Delivery upload failed: ${error.message}`);

  return createDeliverySignedUrl({ path });
}

export async function createDeliverySignedUrl({ path }) {
  if (!path) throw new Error('Delivery package path is required');
  const db = getAdminDb();
  const { data: signed, error } = await db.storage
    .from(BUCKET)
    .createSignedUrl(path, SIGNED_URL_TTL);

  if (signed?.signedUrl) {
    return { bucket: BUCKET, path, signed_url: signed.signedUrl, expires_in: SIGNED_URL_TTL };
  }

  throw new Error(`Could not create delivery URL: ${error?.message || 'unknown error'}`);
}
