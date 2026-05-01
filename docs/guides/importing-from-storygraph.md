# Importing from StoryGraph

BiblioBud reads the standard StoryGraph CSV export.

## Get your StoryGraph export

1. Sign in to StoryGraph.
2. **Profile → Manage Account → Export StoryGraph data**.
3. Download the resulting CSV.

The export is a single file regardless of library size.

## Upload

Web UI: **Settings → Import**, drop the file. Auto-detect picks up
StoryGraph from the column header signature.

API:

```bash
curl -X POST "https://example.com/api/v1/imports?source=storygraph" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "file=@StoryGraph-Export.csv"
```

`?source=storygraph` is optional — auto-detect handles it — but
explicit is fine.

## Field mapping

| StoryGraph column        | BiblioBud field                     | Notes |
|--------------------------|-------------------------------------|-------|
| `Title`                  | `book.title`                        | |
| `Authors`                | `book.authors`                      | Comma-split. |
| `ISBN/UID`               | `book.isbn_13`                      | StoryGraph stores ISBN-13 here when known; non-ISBN UIDs are ignored. |
| `Format`                 | `copies.format` (if owned)          | Mapped to BiblioBud's `format` enum: `hardcover`, `paperback`, `ebook`, `audiobook`, `other`. |
| `Read Status`            | `user_books.status`                 | See mapping below. |
| `Date Added`             | `user_books.created_at`             | |
| `Last Date Read`         | `user_books.finished_at`            | StoryGraph supports multiple read-throughs; we keep the most recent. |
| `Star Rating`            | `user_books.rating`                 | Rounded to nearest integer 1..5; blank → null. |
| `Review`                 | `reviews.body` (private)            | One review per book. |
| `Tags`                   | `tags`                              | Comma-split. **Promoted to tags**, not shelves — see below. |
| `Owned`                  | creates a `Copy` row when truthy    | Idempotent on re-import. |
| `Content Warnings`       | (ignored)                           | StoryGraph-specific; no equivalent in v1. |
| `Moods`                  | (ignored)                           | StoryGraph-specific. |
| `Pace`                   | (ignored)                           | StoryGraph-specific. |

## Status mapping

| StoryGraph `Read Status`    | BiblioBud `user_books.status` |
|-----------------------------|-------------------------------|
| `to-read`                   | `wanted`                      |
| `currently-reading`         | `reading`                     |
| `read`                      | `read`                        |
| `did-not-finish`            | `dnf`                         |

## Tags vs shelves

StoryGraph `Tags` map to BiblioBud **tags** (not shelves), because
StoryGraph users treat them as cross-cutting labels — closer to
BiblioBud's tag mental model than to shelves.

Compare:

- GoodReads custom shelves → BiblioBud bookshelves (buckets).
- StoryGraph tags → BiblioBud tags (cross-cutting labels).

You can hand-promote either way after import (Settings → Library).

## Re-imports

Same idempotency rules as every other importer:

- `user_books` upserts by `(user, book)`. Last-write-wins on the
  scalar fields.
- Tag and shelf membership: PK-deduped.
- Copies with `source=import` are not duplicated unless you pass
  `?duplicate_copies=true`.

## What we lose

StoryGraph's mood / pace / content-warning metadata is **not**
imported. v1 has no schema for it, and we'd rather store nothing
than store it in a shape we'd have to migrate later. If you want
that data preserved verbatim, keep your original StoryGraph export
file — BiblioBud doesn't re-derive it.

If/when v2 grows mood/pace fields, a re-import of the same StoryGraph
file will backfill them.
