# Examples — Imports

`POST /imports` accepts a multipart upload, auto-detects the source
format, and runs the import as a background job. See
[architecture/user-data-import.md](../../architecture/user-data-import.md)
for the design and [guides/](../../guides/) for per-source field
mappings.

```bash
TOKEN=bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d
```

## Upload — auto-detect source

```bash
curl -X POST https://example.com/api/v1/imports \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "file=@goodreads_library_export.csv"
```

```http
HTTP/1.1 202 Accepted
Location: /api/v1/imports/01HQNS9X...

{
  "id": "01HQNS9X...",
  "kind": "goodreads",
  "status": "queued",
  "progress": 0,
  "created_at": "2026-04-30T16:14:02Z"
}
```

`kind` is the auto-detected source. If detection fails, the response
is 400 with `code: import.source_unrecognized` and a list of
supported sources — re-upload with explicit `?source=`.

## Upload — explicit source

```bash
curl -X POST "https://example.com/api/v1/imports?source=storygraph" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "file=@StoryGraph-Export.csv"
```

Valid `source` values: `auto` (default), `goodreads`, `storygraph`,
`librarything`, `bibliobud`, `generic`.

## List supported sources

```bash
curl https://example.com/api/v1/imports/sources \
  -H "Authorization: Bearer $TOKEN"
```

```json
{
  "data": [
    {
      "source": "goodreads",
      "name": "GoodReads",
      "schema_doc_url": "https://example.com/docs/guides/importing-from-goodreads",
      "max_file_size_bytes": 10485760
    },
    {
      "source": "storygraph",
      "name": "StoryGraph",
      "schema_doc_url": "https://example.com/docs/guides/importing-from-storygraph",
      "max_file_size_bytes": 10485760
    }
  ]
}
```

## Poll job status

```bash
JOB=01HQNS9X...

curl https://example.com/api/v1/imports/$JOB \
  -H "Authorization: Bearer $TOKEN"
```

```json
{
  "id": "01HQNS9X...",
  "kind": "goodreads",
  "status": "running",
  "progress": 0.42,
  "counts": {
    "imported": 218,
    "skipped": 4,
    "failed": 1,
    "books_fetched_from_provider": 31
  },
  "errors_preview": [
    {
      "row": 47,
      "isbn": "0123456789",
      "reason": "no provider could resolve this ISBN"
    }
  ],
  "created_at": "2026-04-30T16:14:02Z",
  "completed_at": null
}
```

`status` transitions: `queued → running → succeeded | partial_success | failed`.

`partial_success` is the common case — some rows could not be matched
to a book, but the rest imported cleanly.

## Download the full error CSV

```bash
curl -o errors.csv \
  https://example.com/api/v1/imports/$JOB/errors \
  -H "Authorization: Bearer $TOKEN"
```

CSV columns: `row,source_data,reason`. One row per failure. The
`source_data` column contains the original input row so you can
hand-correct and re-upload if you want.

## Cancel a running job

```bash
curl -X DELETE https://example.com/api/v1/imports/$JOB \
  -H "Authorization: Bearer $TOKEN"
```

If `status` is `queued` or `running`, transitions to `failed` with
reason `cancelled`. If `status` is already terminal, the job is
tombstoned (still queryable for ~30 days) but no work is undone.
Returns 204 either way; 409 with `code: import.job_not_cancellable`
if the job is in a state we can't cancel from.

## Idempotent re-upload

Re-uploading the same file is **safe**. The `user_books` anchor
upserts by `(user, book)`, shelf and tag membership are PK-deduped,
and copies created with `source=import` are skipped if one already
exists for the same `(user, book)`.

If you actually want to create a second copy on re-import:

```bash
curl -X POST "https://example.com/api/v1/imports?duplicate_copies=true" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "file=@library.csv"
```

(Almost no one wants this. It exists for the rare "I really did buy
the same book again" case.)

## File too big

Hosted free-tier instances cap upload size (default 10MB):

```http
HTTP/1.1 413 Payload Too Large
Content-Type: application/problem+json

{
  "code": "import.file_too_large",
  "title": "File too large",
  "status": 413,
  "detail": "Free tier is limited to 10MB per import. Upgrade to lift the limit.",
  "limit_bytes": 10485760,
  "capability": "large_imports"
}
```

The `large_imports` capability removes the cap. Self-host has no cap
unless `BIBLIOBUD_IMPORT_MAX_BYTES` is set.
