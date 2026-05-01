# User data import

Importing should be drag-drop-done. Users shouldn't need to know which
platform they're migrating from — the server detects, parses, and
normalizes everything to the BiblioBud domain model.

## Supported sources (v1)

| Source        | Format       | Auto-detect | Notes |
|---------------|--------------|-------------|-------|
| `goodreads`   | CSV          | yes         | Canonical "Library Export". |
| `storygraph`  | CSV          | yes         | StoryGraph "Export Library". |
| `librarything`| CSV / TSV    | yes         | LibraryThing "Export". |
| `bibliobud`   | JSON         | yes         | Our own export — round-trips. |
| `generic`     | CSV          | no          | Minimal schema. See [generic CSV format](../guides/generic-csv-format.md). |

Adding a new source means:

1. Implement the `Importer` interface in `internal/imports/<source>/`.
2. Register it in `internal/imports/importer.go`.
3. Document it under `docs/guides/importing-from-<source>.md`.

That's it. No schema changes, no domain changes.

## Importer interface

```go
type Importer interface {
    // "goodreads" | "storygraph" | ...
    Source() string

    // Sniff the first ~16KB. Returns confidence in [0.0, 1.0].
    // Anything below 0.5 is treated as "no, this isn't me".
    Detect(head []byte) (confidence float64)

    // Parse the file and emit ImportRecord values one at a time.
    // The error channel surfaces fatal parse errors; per-record errors
    // are emitted as records with their own error fields populated.
    Parse(r io.Reader) (records <-chan ImportRecord, fatal <-chan error)
}

type ImportRecord struct {
    SourceRowNum int

    ISBN13, ISBN10 string
    Title, Author  string  // fallback when ISBN is missing or unmatchable

    Status   domain.ReadingStatus  // wanted | reading | read | dnf | ""
    Rating   *int                   // 1..5
    Shelves  []string               // user's custom shelves
    Tags     []string

    DateRead, DateAdded *time.Time
    Notes               string

    OwnedCopy bool
}
```

Each importer translates platform-specific concepts to BiblioBud's:

- GoodReads "Exclusive Shelf" `to-read|currently-reading|read` →
  `Status` (`wanted|reading|read`).
- GoodReads custom shelves → `Shelves` slice.
- GoodReads "My Rating" → `Rating`.
- StoryGraph "Read Status" → `Status`.
- BiblioBud export → identity mapping.

## Auto-detection

When the client hits `POST /imports` without `?source=` (or with
`?source=auto`), the server:

1. Reads the first 16KB of the upload into memory.
2. Calls `Detect(head)` on every registered importer.
3. Picks the importer with the highest confidence ≥ 0.5.
4. If no importer reaches 0.5, returns 400 with
   `code: import.source_unrecognized` and a list of supported sources
   so the client can prompt the user to pick manually.

Detectors are header-based and fast — they don't parse the whole file.
A typical detector inspects the first row's column names and returns
1.0 if the magic GoodReads / StoryGraph / etc. column set is present,
0.0 otherwise.

## Job lifecycle

```
POST /imports
       │
       ▼
   ┌────────┐    enqueue   ┌──────────┐
   │ queued │ ───────────► │ running  │
   └────────┘              └────┬─────┘
                                │
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
        partial_success    succeeded        failed
        (some rows         (no errors)     (no rows imported,
         failed)                             fatal parse error)
                ▲
                │  most common terminal state
```

Jobs are durable — `import_jobs` rows persist across restarts. A
worker goroutine polls for `queued` jobs and processes them. State
transitions are logged.

The client polls `GET /imports/{job_id}` until `status` is terminal.
The response includes:

- `progress.processed` / `progress.total`
- `progress.imported` / `progress.skipped` / `progress.failed`
- `progress.books_fetched_from_provider` (how many lazy book lookups
  this import triggered)
- `errors_preview` (first 100 row-level errors)
- `errors_url` (download the full error CSV)

## Per-row error handling

The default policy is **fail-soft**: a row that can't be matched to a
canonical book (no ISBN, fallback title/author lookup also misses)
goes into the error list, and the rest of the import continues.

The fatal-error channel is reserved for things that mean the file
itself is unprocessable (corrupted CSV, encoding mismatch). These
transition the job to `failed`.

## Idempotency

Re-uploading the same file is safe:

- `user_books`: keyed on `(user_id, book_id)`. Re-imports last-write-wins
  on status / rating / dates / notes.
- `bookshelf_items`: composite PK `(bookshelf_id, book_id)`. Duplicate
  inserts silently no-op.
- `user_book_tags`: composite PK `(user_id, book_id, tag_id)`. Same.
- `bookshelves`: get-or-create by `(user_id, name)`. Idempotent.
- `tags`: get-or-create by `(user_id, name)`. Idempotent.
- `copies`: This is the surprise. We create a copy only if **no
  existing copy with `source='import'` exists for this `(user, book)`**.
  Without this check, re-uploading would quintuple your library. Power
  users who legitimately want one-row-per-import-mention can set
  `?duplicate_copies=true`.

## Lazy book ingestion during imports

For each `ImportRecord` with an ISBN, the server resolves the canonical
`Book` via the provider chain (see
[book-metadata-sourcing.md](book-metadata-sourcing.md)). This means a
GoodReads import of 500 books will trigger up to 500 Open Library
lookups — but only for books not already in the cache. Subsequent
re-imports hit the local cache.

For records without an ISBN we attempt a title+author search; if that
returns a single high-confidence match, we use it. Otherwise the row
goes into the error list.

## File-size limits

Imports above 10 MB are gated by the `large_imports` capability:

- Self-host: capability granted, no limit.
- Hosted free tier: capability not granted, 413 with
  `code: import.file_too_large`.
- Hosted paid tiers: capability granted.

10 MB is a soft default — typical GoodReads exports are well under.
The constant is configurable via `BIBLIOBUD_IMPORT_FREE_LIMIT_MB`.

## Cancellation

`DELETE /imports/{job_id}`:

- `queued` or `running` → transition to `canceled`. The worker checks
  for cancellation between rows and exits cleanly. Any rows already
  imported stay imported.
- Terminal states → tombstones the job (the row remains for audit, the
  error CSV is purged).

## What is NOT (yet) built

- **Resumable uploads** for very large files. v1 is one-shot multipart.
- **Diff preview** ("here's what would change if you import this").
  Useful for power users; out of scope for v1.
- **Progress streaming** via Server-Sent Events. v1 is poll-based.
