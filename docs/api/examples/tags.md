# Examples — Tags

Tags are per-user labels on the `(user, book)` relationship. They're
cross-cutting — a book can carry any number of tags regardless of
which shelves it's on or what status it has. Use them for personal
namespace ("Gift for Julie", "lent to Mom", "audiobook", "re-read").

```bash
TOKEN=bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d
```

## Create a tag

```bash
curl -X POST https://example.com/api/v1/tags \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{ "name": "Gift for Julie", "color": "#e07a5f" }'
```

```json
{
  "id": "01HQNS7AAA...",
  "name": "Gift for Julie",
  "color": "#e07a5f",
  "books_count": 0,
  "created_at": "2026-04-30T16:10:11Z"
}
```

Tag names must be unique per user; duplicates return 409 with
`code: tag.name_taken`. Color is optional.

## List your tags

```bash
curl https://example.com/api/v1/tags \
  -H "Authorization: Bearer $TOKEN"
```

Returns every tag with its `books_count`. Not paginated.

## Apply a tag to a book

Tags are applied through the library namespace because they describe
the `(user, book)` relationship:

```bash
TAG=01HQNS7AAA...

curl -X POST https://example.com/api/v1/library/9780441013593/tags \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" \
  -d "{ \"tag_id\": \"$TAG\" }"
```

Two side effects:

1. The `books` row is resolved through providers if needed.
2. The `user_books` anchor is upserted.

## Remove a tag from a book

```bash
curl -X DELETE https://example.com/api/v1/library/9780441013593/tags/$TAG \
  -H "Authorization: Bearer $TOKEN"
```

204. The tag itself stays — only the assignment is removed.

## The cross-cutting query

This is the whole point of tags: list every book carrying a tag,
regardless of shelf or status.

```bash
curl "https://example.com/api/v1/tags/$TAG/books?limit=50" \
  -H "Authorization: Bearer $TOKEN"
```

```json
{
  "data": [
    {
      "isbn_13": "9780441013593",
      "book": { "title": "Dune", "authors": ["Frank Herbert"] },
      "status": "read",
      "owned": true,
      "shelves": ["Sci-Fi"]
    },
    {
      "isbn_13": "9780062315007",
      "book": { "title": "The Alchemist", "authors": ["Paulo Coelho"] },
      "status": null,
      "owned": false,
      "shelves": ["Wishlist"]
    }
  ],
  "next_cursor": null
}
```

The two books here live on different shelves, have different
statuses, one is owned and one isn't — but they share a tag, and
that's what binds them.

## Combine with library filters

`/library` accepts `tag=<id>` so you can intersect tags with status
and shelf:

```bash
# "Gifts I haven't sent yet" — tagged but not read.
curl "https://example.com/api/v1/library?tag=$TAG&status=" \
  -H "Authorization: Bearer $TOKEN"
```

Only one `tag=` per request in v1; multi-tag intersection isn't
supported yet. Use `/tags/{id}/books` and intersect client-side if
you need it.

## Rename a tag

```bash
curl -X PATCH https://example.com/api/v1/tags/$TAG \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{ "name": "Gift for Julie 2026", "color": "#3d5a80" }'
```

All existing assignments follow the rename automatically.

## Delete a tag

```bash
curl -X DELETE https://example.com/api/v1/tags/$TAG \
  -H "Authorization: Bearer $TOKEN"
```

Removes the tag and every assignment of it. Books and their `user_books`
anchors stay. Returns 204.
