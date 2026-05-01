# Exporting your data

Your data is yours. BiblioBud has a single endpoint that returns the
full picture: account, library, copies, shelves, tags, reviews,
follows, and import history.

## The endpoint

```bash
curl https://example.com/api/v1/users/me/export \
  -H "Authorization: Bearer $TOKEN" \
  -o bibliobud-export.json
```

Response is `application/json`. The shape is documented in the
OpenAPI spec under the `User` and resource schemas.

## What's in the export

```json
{
  "exported_at": "2026-04-30T17:01:42Z",
  "schema_version": "1",
  "user": { ... },
  "library": [ { "isbn_13": "...", "status": "...", ... } ],
  "copies": [ ... ],
  "bookshelves": [ { "name": "...", "items": [ ... ] } ],
  "tags": [ { "name": "...", "books": [ ... ] } ],
  "reviews": [ ... ],
  "follows": { "following": [...], "followers": [...] },
  "imports": [ { "id": "...", "kind": "goodreads", ... } ]
}
```

## What's NOT in the export

- **Other users' data.** Even reviews you can see on their public
  profile aren't included — those belong to them.
- **Canonical book metadata** beyond ISBN + title + authors.
  `books` rows are shared across users and aren't yours to take.
  Cover URLs and full descriptions you can fetch back from the
  source provider.
- **Session tokens.** Obviously.
- **Password hash.** Obviously.

## Round-tripping

The export format is the same one the `bibliobud` importer accepts:

```bash
curl -X POST "https://other-instance.com/api/v1/imports?source=bibliobud" \
  -H "Authorization: Bearer $OTHER_TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "file=@bibliobud-export.json"
```

This is the supported migration path between BiblioBud instances
(self-host → hosted, or vice versa, or self-host → self-host).

Round-tripping is idempotent — you can re-import to the same instance
the export came from and end up with no duplicates.

## What does *not* round-trip cleanly

- **Created-at timestamps.** Imports stamp `created_at` to "now"
  rather than preserving the original. Domain timestamps
  (`started_at`, `finished_at`, `acquired_at`) **do** round-trip.
- **Internal IDs.** A re-imported book / shelf / tag gets a new
  ID. References between objects (a tag on a book) re-resolve by
  natural key.
- **Other users' follows of you.** Your following list comes back;
  your followers list does not (those follows belong to the other
  users).

## Account deletion

`DELETE /users/me` schedules a hard purge after the soft-delete
grace period. **Take an export before you delete.** Once the purge
runs, the data is gone.

```bash
# Export first, then delete.
curl https://example.com/api/v1/users/me/export \
  -H "Authorization: Bearer $TOKEN" \
  -o bibliobud-export.json

curl -X DELETE https://example.com/api/v1/users/me \
  -H "Authorization: Bearer $TOKEN"
```

Hosted: 30-day soft-delete window. During that window, log in
restores the account exactly as it was. After 30 days, the purge
job hard-deletes everything.

Self-host: `DELETE /users/me` works the same way, but you control
the purge schedule via `BIBLIOBUD_PURGE_AFTER_DAYS`.

## GDPR / data-portability notes

The export endpoint is BiblioBud's GDPR Article 20 (right to data
portability) implementation. The format is JSON, machine-readable,
and structured — meeting the regulation's "structured, commonly
used, machine-readable format" requirement.

`DELETE /users/me` is the Article 17 (right to erasure)
implementation. The 30-day soft-delete window is intentional — it
exists for accidental-click recovery, not as a gate on the right.
You can request immediate hard-delete in writing if you need it for
compliance reasons.
