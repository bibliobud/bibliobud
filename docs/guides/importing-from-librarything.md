# Importing from LibraryThing

LibraryThing offers several export formats. BiblioBud reads the
**TSV** ("Tab Separated Values") and CSV exports.

## Get your LibraryThing export

1. Sign in to LibraryThing.
2. **More → Import/Export**.
3. Under **Export**, choose **Tab-delimited file** (recommended) or
   **Comma-separated values**.
4. Download.

The TSV form is preferred because LibraryThing's CSV escaping is
loose — books with commas in titles can confuse stricter parsers.
BiblioBud handles both, but TSV is more reliable for large libraries.

## Upload

```bash
curl -X POST "https://example.com/api/v1/imports?source=librarything" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "file=@librarything_export.tsv"
```

Auto-detect handles both formats; you can omit `?source=`.

## Field mapping

LibraryThing's columns are catalog-oriented (LCC, Dewey, languages),
while BiblioBud's model is reader-oriented (status, rating, shelves).
We import everything that has a clean home and skip the rest.

| LibraryThing column        | BiblioBud field                  | Notes |
|----------------------------|----------------------------------|-------|
| `Book Id`                  | (ignored)                        | Internal to LibraryThing. |
| `Title`                    | `book.title`                     | |
| `Primary Author`           | `book.authors[0]`                | |
| `Other Authors`            | `book.authors[1..]`              | |
| `ISBN`                     | `book.isbn_13`                   | Normalized from ISBN-10 if needed. |
| `Publication`              | `book.publisher`, `book.published_date` | Best-effort split. |
| `Pages`                    | `book.page_count`                | |
| `Tags`                     | `tags`                           | Promoted to tags. |
| `Collections`              | `bookshelves`                    | Promoted to shelves. **`Your library`** is treated as "owned" and creates a `Copy`. |
| `Rating`                   | `user_books.rating`              | LibraryThing uses 0..5 with halves; we round to nearest 1..5, 0 → null. |
| `Review`                   | `reviews.body` (private)         | |
| `Date Started`             | `user_books.started_at`          | |
| `Date Read`                | `user_books.finished_at`         | |
| `Date Acquired`            | `copies.acquired_at` (if owned)  | |
| `Date Entered`             | `user_books.created_at`          | |
| `Lexile`, `Dewey`, etc.    | (ignored)                        | Catalog metadata; no v1 home. |
| `LCC`, `BCID`              | (ignored)                        | |

## Status mapping

LibraryThing has no built-in reading-status field. We infer status
from `Collections`:

| LibraryThing collection      | BiblioBud `status` |
|------------------------------|--------------------|
| `Currently reading`          | `reading`          |
| `To read` / `Wishlist`       | `wanted`           |
| `Read but unowned`           | `read`             |
| `Read`                       | `read`             |
| (any other collection)       | unset              |

If a row appears in **`Your library`**, the importer creates a
`Copy` row even if no other collection implies a status — owning a
book without having read it is normal.

If a row's status is implied by the presence of `Date Read` but
none of the above collections match, status is set to `read`.

Custom collections become BiblioBud bookshelves with the same name.

## Re-imports

Idempotent, same as every other importer:

- `user_books` upserts.
- Tags and shelf membership PK-deduped.
- Copies with `source=import` not duplicated.

## What we lose

LibraryThing's catalog metadata (Dewey, LCC, Lexile, BCID) is not
imported — BiblioBud is a reader-oriented tool, not a catalog. Keep
your LibraryThing export if you need that data preserved.
