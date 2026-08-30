import { getAdminDb } from './db.js';

const BUCKET = process.env.DELIVERY_BUCKET || 'deliveries';

export async function uploadDeliveryPackage({ projectId, zipBuffer, fileName }) {
  const db = getAdminDb();
  const path = `${projectId}/${fileName}`;

  const { error } = await db.storage.from(BUCKET).upload(path, zipBuffer, {
    contentType: 'application/zip',
    upsert: true,
    cacheControl: '3600'
  });
  if (error) throw new Error(`Delivery upload failed: ${error.message}`);

  const { data: signed, error: signedError } = await db.storage
    .from(BUCKET)
    .createSignedUrl(path, 60 * 60 * 24);
  if (signedError || !signed?.signedUrl) {
    throw new Error(`Could not create delivery URL: ${signedError?.message || 'unknown error'}`);
  }

  return { bucket: BUCKET, path, signed_url: signed.signedUrl, expires_in: 86400 };
}
