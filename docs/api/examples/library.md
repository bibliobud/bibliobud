# Examples — Library

The `/library` resource is the user-book relationship: status,
rating, dates, notes. It does not represent ownership — that's
[copies](#) — and it doesn't represent shelf membership.

All examples assume `TOKEN` is set:

```bash
TOKEN=bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d
```

## Mark a book as "wanted"

```bash
curl -X PUT https://example.com/api/v1/library/9780441013593 \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{ "status": "wanted" }'
```

This `PUT` is an upsert. If the user has never touched this ISBN, the
server resolves it through the metadata provider chain (creating the
`books` row if needed) and creates a `user_books` anchor.

```json
{
  "isbn_13": "9780441013593",
  "book": {
    "title": "Dune",
    "authors": ["Frank Herbert"],
    "cover_url": "https://covers.openlibrary.org/b/id/12345-L.jpg"
  },
  "status": "wanted",
  "rating": null,
  "started_at": null,
  "finished_at": null,
  "notes": "",
  "owned": false,
  "tags": [],
  "shelves": [],
  "copies_count": 0
}
```

## Start reading

```bash
curl -X PUT https://example.com/api/v1/library/9780441013593 \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "status": "reading",
    "started_at": "2026-04-01"
  }'
```

`PUT` replaces the writable fields. Fields you don't send keep their
current value (this is documented per-field in the OpenAPI spec —
some fields explicitly clear on omit).

## Finish and rate

```bash
curl -X PUT https://example.com/api/v1/library/9780441013593 \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "status": "read",
    "finished_at": "2026-04-29",
    "rating": 5,
    "notes": "Holds up. The Litany Against Fear still hits."
  }'
```

## List your library

```bash
curl "https://example.com/api/v1/library?limit=25" \
  -H "Authorization: Bearer $TOKEN"
```

Response:

```json
{
  "data": [
    {
      "isbn_13": "9780441013593",
      "book": { "title": "Dune", "authors": ["Frank Herbert"] },
      "status": "read",
      "rating": 5,
      "owned": true,
      "tags": ["sci-fi", "favorites"],
      "shelves": ["Sci-Fi"],
      "copies_count": 1
    }
  ],
  "next_cursor": null,
  "total_estimate": 1
}
```

## Filter by status

```bash
curl "https://example.com/api/v1/library?status=reading&limit=25" \
  -H "Authorization: Bearer $TOKEN"
```

Filters compose with `tag=<id>` and `shelf=<id>`:

```bash
curl "https://example.com/api/v1/library?status=read&tag=01HXX...&shelf=01HYY..." \
  -H "Authorization: Bearer $TOKEN"
```

## Get one book in the library

```bash
curl https://example.com/api/v1/library/9780441013593 \
  -H "Authorization: Bearer $TOKEN"
```

Returns the same shape as a list item, plus `copies` (full Copy
records) and the full tag and shelf lists.

If the user has never touched this ISBN, returns 404 with
`code: library.anchor_not_found`. The `books` row may still exist —
this is "is *Dune* in **my** library?", not "does *Dune* exist?".

## Remove from library

```bash
curl -X DELETE https://example.com/api/v1/library/9780441013593 \
  -H "Authorization: Bearer $TOKEN"
```

Removes the anchor, all tag assignments, and all shelf memberships.
**Copies are preserved** — the user might have given the book away
but still want the inventory record. To delete copies in the same
call:

```bash
curl -X DELETE "https://example.com/api/v1/library/9780441013593?with_copies=true" \
  -H "Authorization: Bearer $TOKEN"
```

204 in both cases. A subsequent GET returns 410 Gone for 30 days,
then 404.

## Working with copies

A `Copy` is a per-user physical or digital instance. Multiple copies
per `(user, book)` are allowed (gift case, signed first edition + a
reading copy, etc.).

```bash
# Add a copy — auto-creates the user_books anchor if it isn't there.
curl -X POST https://example.com/api/v1/copies \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{
    "isbn": "9780441013593",
    "condition": "good",
    "format": "paperback",
    "edition": "Ace 1990 reissue",
    "signed": false,
    "acquired_at": "2024-12-25",
    "notes": "Gift from Mom"
  }'
```

```bash
# Soft-delete a copy. Status, tags, shelves, and rating are unaffected.
curl -X DELETE https://example.com/api/v1/copies/01HQNRC2... \
  -H "Authorization: Bearer $TOKEN"
```

After the only non-deleted copy is removed, `library/{isbn}` reports
`owned: false` but the rest of the relationship persists.
