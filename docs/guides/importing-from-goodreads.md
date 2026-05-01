# Importing from GoodReads

BiblioBud can import the canonical GoodReads "Library Export" CSV
end-to-end: books, statuses, ratings, dates, custom shelves, and
review text. No manual cleanup required.

## Get your GoodReads export

1. Sign in to GoodReads.
2. Visit [goodreads.com/review/import](https://www.goodreads.com/review/import).
3. Click **Export Library**. Wait for the link to appear (a few seconds
   to a few minutes depending on library size).
4. Download `goodreads_library_export.csv`.

## Upload to BiblioBud

In the web UI: **Settings → Import → Upload file**, drop the CSV.
Source detection will identify it automatically.

Via the API:

```bash
curl -X POST https://example.com/api/v1/imports \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "file=@goodreads_library_export.csv"
```

The response includes a job ID — poll `/imports/{id}` for progress.

## Field mapping

| GoodReads column            | BiblioBud field                  | Notes |
|-----------------------------|----------------------------------|-------|
| `Book Id`                   | (ignored)                        | Internal to GoodReads. |
| `Title`                     | `book.title`                     | Used as fallback if ISBN can't be resolved. |
| `Author`                    | `book.authors[0]`                | GoodReads stores additional authors in `Additional Authors`. |
| `Additional Authors`        | `book.authors[1..]`              | Comma-split. |
| `ISBN` / `ISBN13`           | `book.isbn_13`                   | ISBN-10 is normalized to ISBN-13. |
| `My Rating`                 | `user_books.rating`              | 0 → null, 1..5 preserved. |
| `Average Rating`            | (ignored)                        | We don't track aggregate ratings on book rows. |
| `Publisher`, `Binding`, etc.| `book.*`                         | Used to enrich the `books` row if not already present. |
| `Number of Pages`           | `book.page_count`                | |
| `Year Published`            | `book.published_date` (year only)| |
| `Date Read`                 | `user_books.finished_at`         | |
| `Date Added`                | `user_books.created_at` (initial)| Not exposed via API. |
| `Bookshelves`               | mixed — see below                | |
| `Exclusive Shelf`           | `user_books.status`              | See mapping below. |
| `My Review`                 | → `reviews.body` (private)       | One review per book; second imports overwrite. |
| `Read Count`                | (ignored)                        | |
| `Owned Copies` > 0          | creates a `Copy` row             | One copy per imported row even if value > 1; pass `?duplicate_copies=true` to opt out of dedup. |

## Status mapping

GoodReads has three "exclusive" shelves; BiblioBud treats them as
status, **not** as bookshelves:

| GoodReads exclusive shelf | BiblioBud `user_books.status` |
|---------------------------|-------------------------------|
| `to-read`                 | `wanted`                      |
| `currently-reading`       | `reading`                     |
| `read`                    | `read`                        |

If you have other "exclusive" shelves configured in GoodReads (some
users do), they're treated as custom shelves — see below.

## Custom shelves

Every shelf in `Bookshelves` that **isn't** one of the three
reserved names becomes a BiblioBud `Bookshelf` row in your account,
and the book is added to it.

So a GoodReads row with `Bookshelves = "read, sci-fi, hugo-winners"`
maps to:

- `status = read`
- shelf membership: `Sci-Fi`, `Hugo Winners` (created if absent)

Shelf names are lightly normalized (whitespace trimmed, dashes ↔
spaces standardized) but otherwise preserved.

## What about tags?

GoodReads doesn't have first-class tags — its "shelves" are the
closest equivalent. We map all custom shelves to BiblioBud
**bookshelves**, not tags. Once imported, you can hand-promote the
ones you'd rather use as tags (Settings → Library → Convert shelf
to tag) — that's a one-click operation that creates a tag from the
shelf, copies the membership, and deletes the shelf.

We chose this default because GoodReads users overwhelmingly treat
their shelves as buckets, and BiblioBud's `Bookshelf` is the closer
match for that mental model.

## When ISBNs can't be resolved

For each row, the importer:

1. Tries the ISBN against the metadata provider chain (Open Library,
   then ISBNdb if configured).
2. If that fails, falls back to title + author search.
3. If that also fails, the row is recorded in the job's error list
   with `reason: "no provider could resolve this ISBN"` (or
   `"no provider could match title + author"`). The rest of the
   import continues.

Failed rows do **not** abort the job. Status will be
`partial_success` if any failed.

You can download the full error list as CSV:

```bash
curl -o errors.csv \
  https://example.com/api/v1/imports/{job_id}/errors \
  -H "Authorization: Bearer $TOKEN"
```

Hand-correct ISBNs and re-upload — the import is idempotent, so
already-imported books are upserted, not duplicated.

## Re-imports are safe

Upload the same file again and:

- `user_books` rows upsert (status / rating / dates overwrite —
  last-write-wins is intentional, so corrected GoodReads data
  propagates).
- Shelf and tag memberships are deduplicated.
- Copies created with `source=import` for the same `(user, book)`
  are not duplicated.

## Limits

Hosted free tier caps upload size at 10MB (capability:
`large_imports` lifts it). Self-hosted instances have no cap unless
`BIBLIOBUD_IMPORT_MAX_BYTES` is set.

A typical GoodReads export is well under 10MB even for libraries in
the tens of thousands.
