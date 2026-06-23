# R2/S3 storage runbook

This backend already supports S3-compatible object storage. Use this runbook to switch Railway uploads from ephemeral local disk to Cloudflare R2 and to audit or backfill existing files.

## Required Railway variables

Set these on the Railway backend service:

```env
STORAGE_DRIVER=s3
PUBLIC_UPLOADS=false
S3_BUCKET=<r2-bucket-name>
S3_ACCESS_KEY_ID=<r2-access-key-id>
S3_SECRET_ACCESS_KEY=<r2-secret-access-key>
S3_ENDPOINT=https://<cloudflare-account-id>.r2.cloudflarestorage.com
S3_REGION=auto
S3_FORCE_PATH_STYLE=true
S3_KEY_PREFIX=photos
VERIFY_STORAGE_ON_START=true
```

Use an R2 S3 API access key pair. Do not use a general Cloudflare dashboard API token as `S3_ACCESS_KEY_ID` or `S3_SECRET_ACCESS_KEY`.

To actually configure the live Railway service you need all of these real values:

- Cloudflare account id, used only inside `S3_ENDPOINT`.
- R2 bucket name, used as `S3_BUCKET`.
- R2 S3 access key id, used as `S3_ACCESS_KEY_ID`.
- R2 S3 secret access key, used as `S3_SECRET_ACCESS_KEY`.
- Railway project/service access, either via Railway dashboard or `RAILWAY_TOKEN` plus project/service ids.

Do not commit these values. Put them in Railway Variables and, for local verification only, in a gitignored `.env.local`.

## Verify before redeploy

Create a gitignored local env file such as `../.env.local` or pass real variables through the shell:

```env
PROD_DATABASE_URL=postgresql://...
STORAGE_DRIVER=s3
PUBLIC_UPLOADS=false
R2_ACCOUNT_ID=<cloudflare-account-id>
S3_BUCKET=...
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
# Optional when R2_ACCOUNT_ID is set; helper scripts derive it:
S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
S3_REGION=auto
S3_FORCE_PATH_STYLE=true
S3_KEY_PREFIX=photos
```

Then run:

```powershell
cd backend
npm run storage:verify -- --env=../.env.local
```

The command writes, reads, and deletes one temporary object. It prints only redacted env status.

The backend performs the same write/read/delete verification during production startup when `VERIFY_STORAGE_ON_START=true` (default in production). Keep it enabled so a bad R2 key or bucket stops deploy before workers can upload files.

After deploy, an admin can run the same live check through the API:

```powershell
curl -X POST https://<backend-domain>/api/admin/storage/verify `
  -H "Authorization: Bearer <admin-token>"
```

Expected result:

```json
{
  "ok": true,
  "storage": {
    "driver": "s3",
    "publicUploads": false
  },
  "checkedAt": "..."
}
```

To print the exact Railway Variables block from the local env file:

```powershell
cd backend
npm run storage:railway-env -- --env=../.env.local
```

Review the output, then paste it into Railway Variables. The command intentionally does not call Railway by itself.

## Audit existing DB records

```powershell
cd backend
npm run storage:audit -- --env=../.env.local
```

Optional API endpoint audit:

```env
PROD_API_BASE_URL=https://firemni-production.up.railway.app
PROD_API_TOKEN=<existing-bearer-token>
```

With those two values present, the audit also checks:

- `GET /api/photos/:id/file`
- `GET /api/jobs/:jobId/floors/:floorId/drawing/file`

## Backfill local uploads into R2

Dry run first:

```powershell
cd backend
npm run storage:backfill-local -- --env=../.env.local
```

Write recovered local files to R2 under the same DB keys:

```powershell
cd backend
npm run storage:backfill-local -- --env=../.env.local --write
```

If recovered files are not in `backend/uploads`, set:

```env
LOCAL_UPLOAD_PATH=C:\path\to\recovered\uploads
```

The storage service adds `S3_KEY_PREFIX`, so DB `file_path` value `abc.webp` is stored as `photos/abc.webp` when `S3_KEY_PREFIX=photos`.

## Controlled deployment

1. Stop ordinary uploads until R2 verification passes.
2. Set Railway variables above.
3. Redeploy the backend once.
4. Confirm `GET /ready` returns `200`.
5. Run `POST /api/admin/storage/verify` with an admin bearer token.
6. Upload and download one seal photo and one floor drawing.
7. Confirm the new objects exist in R2 under `photos/`.
8. Run `storage:audit` again and backfill any recoverable missing files.
