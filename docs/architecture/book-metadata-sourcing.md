# Book metadata sourcing

The `books` table is BiblioBud's shared canonical view of every book
any user on the instance has ever touched. It is **never** bulk-seeded
from a third-party dump. Books enter the cache lazily, on first
lookup, fetched from configured metadata providers.

## Why lazy

- **Footprint**: Open Library's full dump is tens of gigabytes. A
  self-hoster running BiblioBud on a Raspberry Pi shouldn't need to
  ingest it.
- **Freshness**: cached metadata can be refreshed on demand or on a
  schedule. A bulk seed is stale the moment it's loaded.
- **Licensing**: shipping someone else's dataset opens questions about
  redistribution rights. Pulling on demand against a documented API
  doesn't.

## Provider interface

```go
type BookMetadataProvider interface {
    Name() string  // "open_library" | "isbndb" | ...

    LookupByISBN(ctx context.Context, isbn string) (*domain.Book, error)
    Search(ctx context.Context, q SearchQuery) ([]domain.Book, error)
    Capabilities() ProviderCapabilities
}

type SearchQuery struct {
    Free   string
    Title  string
    Author string
    ISBN   string
    Limit  int
}

type ProviderCapabilities struct {
    Search       bool
    Covers       bool
    Conditional  bool  // supports ETag / If-None-Match
}
```

v1 ships two implementations:

- `internal/books/openlibrary/` — free, default, always on.
- `internal/books/isbndb/` — paid, optional, configured via
  `BIBLIOBUD_ISBNDB_API_KEY`. Better metadata for newer / niche books.

New providers (Google Books, BNB, Worldcat) drop in by implementing the
interface. The provider registry is wired in `cmd/bibliobud/main.go`.

## Resolver chain

`internal/books/resolver.go` wraps providers with caching, negative
caching, rate limiting, and circuit breaking. Configured priority order
via env:

```
BIBLIOBUD_BOOK_PROVIDERS=openlibrary,isbndb
```

Left = first tried.

### `LookupByISBN(isbn)` flow

```
                 ┌─────────────────────────┐
                 │  GET /books/{isbn}      │
                 └────────────┬────────────┘
                              │
                  ┌───────────▼──────────┐
                  │ books table cache    │
                  └─────┬──────┬─────────┘
                   hit  │      │  miss
                        ▼      ▼
        return + async-refresh │
        if fetched_at > 30d    ▼
                       ┌──────────────────┐
                       │ negative cache   │
                       │ book_lookup_     │
                       │   misses         │
                       └──────┬───┬───────┘
                          hit │   │ miss
                              ▼   ▼
                     return 404   walk providers
                                  in priority order
                                       │
                          ┌────────────┼─────────────┐
                          ▼            ▼             ▼
                    open_library    isbndb       (next provider…)
                          │            │             │
                          └─────┬──────┴─────────────┘
                                │ first non-error wins
                                ▼
                       persist to books
                       return
                                │
                                ▼ (all providers exhausted)
                       persist to negative cache
                       return 404
```

### `Search(query)` flow

1. Query the local FTS index.
2. If results count >= threshold (default 5) and `?fresh=true` is not
   set, return immediately.
3. Otherwise fan out to every provider with `Search` capability in
   parallel, with a per-provider timeout (default 3s).
4. Merge results, dedupe by ISBN-13. Local results outrank provider
   results.
5. Return to caller. Newly seen books are persisted in a background
   goroutine — the request does not block on writes.

## Per-provider rate limiting

Each provider has a token bucket. Defaults:

- `openlibrary`: 100 requests / 5 minutes (matches their published
  guidance).
- `isbndb`: configurable; depends on the user's plan.

When a provider hits its rate limit, the resolver skips to the next
one. When all providers are rate-limited or unhealthy, lookups return
503, the book row is **not** created, and the negative cache is **not**
populated.

## Circuit breaker

If a provider returns 5xx or times out for 5 consecutive requests, the
resolver marks it unhealthy and skips it for a 60-second cooldown. The
next request after cooldown is a probe — if it succeeds, the provider
is reinstated.

This prevents one flaky provider from cascading into user-visible
errors as long as a healthy provider is configured.

## Forced refresh

```
POST /api/v1/books/refresh/{isbn}
```

Bypasses both the cache and the negative cache. Capability-gated by
`metadata_refresh`:

- Self-host: always allowed (capability is granted).
- Hosted free tier: allowed but rate-limited per user (e.g. 10/day).
- Hosted paid tiers: higher per-user quotas.

The 30-day async refresh on `LookupByISBN` is automatic and not gated.

## Manual entry

Users can add books that no provider knows about:

```
POST /api/v1/books
{
  "isbn_13": "9999999999999",
  "title": "Self-Published Friend's Novel",
  "authors": ["Friend Name"],
  ...
}
```

Capability-gated by `manual_book_entry` (free on self-host; gated on
hosted to mitigate abuse — see "Hosted-mode scoping" below).

Manual rows are marked `source='manual'`. A subsequent lookup on the
same ISBN returns the manual row from the cache and never hits the
providers. If the providers later add the book, the row can be
refreshed.

### Hosted-mode scoping

On hosted instances, manual rows have a non-null `created_by_user_id`
and are scoped to that user's library queries. We do this so a typo by
one user doesn't pollute the global search index that everyone else
sees. On self-host (single-org) instances this column is ignored.

## Negative cache details

```
book_lookup_misses
  isbn (PK)
  last_attempted_at
  providers_tried text[]   -- the providers that confirmed "not found"
```

Hits from the negative cache return 404 immediately and do not consume
a provider rate-limit token. TTL: 24 hours since `last_attempted_at`.
A periodic GC job removes entries older than 7 days.

When `POST /books/refresh/{isbn}` fires, the negative cache row is
deleted before the providers are walked.

## What is NOT (yet) built

- **Cover image proxy / CDN**. Currently we surface `cover_url` from the
  provider directly. Hot-linking is fine for development; production
  hosted should proxy + cache covers.
- **Conditional GETs** (ETag / If-None-Match) on the 30-day refresh.
  The interface allows it; no provider impl uses it yet.
- **Search ranking signals** beyond exact-match. v1 returns provider
  ordering.
