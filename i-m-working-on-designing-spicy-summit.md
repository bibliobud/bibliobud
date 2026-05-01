# BiblioBud API Design

## Context

BiblioBud is a greenfield, AGPL-3.0 open-source GoodReads alternative with two deployment modes that share one codebase:

- **Hosted** (bibliobud.com) — multi-tenant SaaS; auth via Firebase; paid features gated per-user via Stripe.
- **Self-hosted** — single Docker container; built-in password auth; every user has every feature with no billing.

The repo is empty (README + LICENSE + SECURITY only). This plan defines the API surface, conventions, and documentation structure that the initial implementation will be built against. The README explicitly carves third-party REST clients out of the AGPL's derivative-work scope, so the JSON API is a first-class public contract — not just an HTMX backend.

Driving design tensions:
- One binary, two modes (hosted vs self-host) without `if hosted {}` scattered everywhere.
- HTMX UI and a stable JSON API for third parties, without the JSON contract drifting from internal handler ergonomics.
- Future Stripe entitlements without painting the v1 schema into a corner.

## Decisions

| # | Decision |
|---|---|
| 1 | Router: `net/http` (Go 1.22+ ServeMux). No Chi. Update README to match. |
| 2 | Split routes: HTML/HTMX under `/`, JSON API under `/api/v1/`. Shared service layer, separate handler packages. |
| 3 | Pluggable `AuthProvider` interface; `firebase` (hosted) and `local` (self-host) implementations selected via `BIBLIOBUD_AUTH=firebase\|local`. |
| 4 | **Plan-based** entitlements: `User → Plan → []Capability`. Self-host hardcodes `plan=unlimited`. Stripe (future) mutates plan, never capabilities directly. |
| 5 | One opaque session token; cookie for HTML, `Authorization: Bearer` for JSON; same DB-backed sessions table. JWTs deferred. |
| 6 | RFC 7807 errors with extension `code` field (stable machine-readable identifier). |
| 7 | Cursor pagination (`?cursor=&limit=`). Offset is banned. |
| 8 | Soft-delete (`deleted_at`) on user-owned resources; 30-day purge job; GDPR export endpoint. |
| 9 | OpenAPI split source under `api/` with `$ref`s; bundled at build time via `redocly bundle` into `api/openapi.bundled.yaml` for codegen consumers and binary embed. |
| 10 | Canonical `Book` (one row per ISBN, sourced from Open Library / ISBNdb). Shared across all users — same ISBN = same row. |
| 11 | `user_books` anchor row per `(user_id, book_id)` carries reading status, rating, started/finished timestamps. Auto-created on first reference (shelf add, copy purchase, tag assign). |
| 12 | `Copy` retained as distinct entity: per-user physical instance with `condition`, `edition`, `signed`, `notes`, `acquired_at`. Multiple copies of one book per user supported (gift case). |
| 13 | "Owned" is **derived**, not a status: `owned ⇔ EXISTS non-deleted copy`. Status enum is reading-state only: `wanted \| reading \| read \| dnf` (nullable). |
| 14 | `Bookshelf` = 100% user-defined virtual buckets (genres, themes, projects). **No system shelves.** Shelf items reference `Book` directly so aspirational books can be shelved without ownership. |
| 15 | `Tag` = per-user, cross-cutting labels on the `(user, book)` relationship. Filterable across the user's library; `/tags/{id}/books` returns every book sharing a tag. Personal namespace ("Gift for Julie", "audiobook", "lent to Mom"). |
| 16 | GoodReads CSV import maps reserved shelves (to-read, currently-reading, read) to `status`; custom shelves become `Bookshelf` rows. |

## Architecture

```
cmd/bibliobud/main.go              -- entry, wires config → providers → router

internal/
  domain/                          -- pure types: User, Book, UserBook, Copy, Bookshelf, Tag, Review, Plan, Capability
  auth/
    provider.go                    -- AuthProvider interface + Principal type
    firebase/                      -- hosted impl (verifies ID token once, mints local session)
    local/                         -- self-host impl (bcrypt + sessions table)
    session.go                     -- shared session store (DB-backed, opaque tokens)
  entitlements/
    resolver.go                    -- Resolve(userID) → Plan + []Capability, cached w/ webhook bust
    middleware.go                  -- requireCapability(CapX) — no-op in self-host
  books/                           -- canonical Book lookup/cache (resolver chain)
    provider.go                    -- BookMetadataProvider interface
    openlibrary/                   -- impl
    isbndb/                        -- impl
    resolver.go                    -- ordered chain, negative cache, rate-limit per provider
  library/                         -- user_books anchor (status/rating/dates); per-user library view
  copies/                          -- physical-instance CRUD
  bookshelves/                     -- shelves + shelf items (user-defined buckets)
  tags/                            -- per-user tags + cross-cutting filter
  reviews/
  imports/                         -- user data import (multi-source)
    importer.go                    -- Importer interface + auto-detect dispatcher
    goodreads/                     -- GoodReads CSV
    storygraph/                    -- StoryGraph CSV
    librarything/                  -- LibraryThing export
    bibliobud/                     -- BiblioBud's own export format (round-trip)
    generic/                       -- minimal CSV (ISBN + status)
    job.go                         -- async runner, progress, per-row error capture
  exports/                         -- GDPR/data-portability JSON export
  storage/
    sqlite/  postgres/             -- two backends behind one repo interface
  httpapi/                         -- JSON handlers under /api/v1/
    errors.go                      -- RFC 7807 + stable codes
    pagination.go                  -- cursor encode/decode
    middleware/                    -- auth, ratelimit, idempotency, requestid, logging
  web/                             -- HTML/HTMX handlers + Templ components
  config/                          -- env-driven config

api/
  openapi.yaml                     -- entry, $refs into paths/ and components/
  paths/                           -- one file per resource group
  components/schemas/              -- one file per schema
  openapi.bundled.yaml             -- generated; embedded into binary, served at /api/v1/openapi.yaml

docs/                              -- see "Documentation Outline" below
```

## Core Data Model

```
books                              CANONICAL — shared across all users
  id (uuid), isbn_13 (unique), isbn_10, title, subtitle, authors[], publisher,
  published_date, page_count, language, cover_url, description,
  source ('open_library' | 'isbndb' | 'manual'), source_id, fetched_at

user_books                         ANCHOR — per (user, book); auto-created on first reference
  user_id, book_id, status (NULL | 'wanted' | 'reading' | 'read' | 'dnf'),
  rating (1..5, null), started_at, finished_at, notes, deleted_at
  PRIMARY KEY (user_id, book_id)

copies                             PHYSICAL — user's owned instances; 0..N per (user, book)
  id, user_id, book_id, condition ('new'|'good'|'fair'|'poor'|'unknown'),
  edition, format ('hardcover'|'paperback'|'ebook'|'audiobook'|'other'),
  signed (bool), acquired_at, notes, deleted_at
  -- Derived: a book is "owned" by user iff EXISTS non-deleted copy.

bookshelves                        USER-DEFINED VIRTUAL SHELVES
  id, user_id, name, description, sort_order, deleted_at
  UNIQUE (user_id, name)
  -- No system/reserved shelves. Status enum covers to-read/reading/read.

bookshelf_items                    SHELF MEMBERSHIP
  bookshelf_id, book_id, added_at
  PRIMARY KEY (bookshelf_id, book_id)
  -- References Book directly, NOT user_books or copy. Aspirational books shelve fine.
  -- Adding a book to any shelf upserts the user_books anchor.

tags                               PER-USER, CROSS-CUTTING LABELS
  id, user_id, name, color (optional), deleted_at
  UNIQUE (user_id, name)

user_book_tags                     TAG ASSIGNMENT
  user_id, book_id, tag_id
  PRIMARY KEY (user_id, book_id, tag_id)
  -- Tags attach to the (user, book) relationship, not to copies, not to shelves.

reviews                            ONE PER (user, book)
  id, user_id, book_id, body, rating, visibility ('private'|'public'),
  created_at, updated_at, deleted_at
  UNIQUE (user_id, book_id) WHERE deleted_at IS NULL

follows                            SOCIAL — directed
  follower_id, followee_id, created_at
  PRIMARY KEY (follower_id, followee_id)

users                              ACCOUNT
  id, email, username (unique), display_name, public_profile (bool),
  external_auth_provider, external_auth_id, password_hash (local mode only),
  created_at, deleted_at

sessions                           AUTH — opaque tokens
  token (unique), user_id, expires_at, last_seen_at, created_at, revoked_at

user_entitlements                  HOSTED MODE — Stripe-backed
  user_id, plan, status, valid_until, stripe_customer_id, stripe_subscription_id

import_jobs                        BACKGROUND JOBS — GoodReads CSV etc.
  id, user_id, kind, status, progress, errors, created_at, completed_at
```

**Reading these together:**
- "Is *Dune* in my library?" → join `user_books` for the user, filter to `book.isbn_13 = X`. If a row exists with non-null status OR any `copy` row exists OR any `bookshelf_item` references it, it's tracked.
- "Do I own *Dune*?" → `EXISTS copies WHERE user_id AND book_id AND deleted_at IS NULL`.
- "Show me everything tagged 'Gift for Julie'" → join `user_book_tags` → `books`. Cross-cuts shelves and status.
- "Books on my Sci-Fi shelf I haven't read" → `bookshelf_items` ⨝ `user_books` filtered by `status IS NULL OR status != 'read'`.

## API Surface

### Conventions

- **Base**: `/api/v1`. Breaking changes bump to `/api/v2`.
- **Auth**: `Authorization: Bearer <opaque-session-token>` OR `Cookie: bb_session=<same-token>`. Same token, two transports.
- **Pagination**: `GET /resource?cursor=<opaque>&limit=<1..100>` → response `{ "data": [...], "next_cursor": "..." | null }`.
- **Idempotency**: `Idempotency-Key: <client-uuid>` honored on all `POST` that create resources; 24h dedup window.
- **Errors**: RFC 7807 JSON: `{ "type": "https://bibliobud.com/errors/entitlement-required", "title": "...", "status": 402, "detail": "...", "code": "entitlement.required", "capability": "analytics" }`. Stable string under `code` is the contract; `title` is for humans.
- **Soft delete**: `DELETE` returns 204 and sets `deleted_at`; resources return 410 Gone for 30 days, then 404.
- **Timestamps**: RFC 3339 UTC.
- **Capability gating**: endpoints requiring a paid capability return 402 with `code: "entitlement.required"` and `capability: "<name>"`. In self-host the middleware short-circuits to allow.

### Routes (JSON API — `/api/v1`)

**Auth & session**
```
POST   /auth/signup                       (local only — 404 in firebase mode)
POST   /auth/login                        (local only)
POST   /auth/firebase/exchange            (firebase only — body: id_token; returns session)
POST   /auth/logout
POST   /auth/password/reset/request       (local only)
POST   /auth/password/reset/confirm       (local only)
GET    /auth/me                           (current Principal + plan + capabilities)
```

**Users & profile**
```
GET    /users/me
PATCH  /users/me
DELETE /users/me                          (soft-delete, schedules purge)
GET    /users/me/export                   (GDPR — full JSON dump of user data)
GET    /users/{username}                  (public profile if user opted in)
```

**Books (canonical, shared)**
```
GET    /books/{isbn}                      (lookup; on miss, fetch Open Library/ISBNdb, persist, return)
GET    /books/search?q=&author=&isbn=     (local index first, third-party fallback)
POST   /books/refresh/{isbn}              (force re-fetch metadata from source; rate-limited)
```

**Library (user-book relationship: status/rating/dates/notes)**
```
GET    /library?status=&tag=&shelf=&cursor=&limit=
                                          (paginated. Expands to include status, owned-flag,
                                           tag list, shelf list, copy count per book)
GET    /library/{isbn}                    (one user_books row + copies + tags + shelves)
PUT    /library/{isbn}                    (upsert; sets status/rating/dates/notes;
                                           creates anchor if absent)
DELETE /library/{isbn}                    (remove all tracking: anchor + tags + shelf membership.
                                           Copies preserved unless ?with_copies=true)
```

**Copies (physical instances)**
```
GET    /copies                            (flat list of user's owned instances)
POST   /copies                            (body: { isbn, condition?, edition?, format?, signed?,
                                            acquired_at?, notes? }; auto-creates user_books anchor)
GET    /copies/{id}
PATCH  /copies/{id}
DELETE /copies/{id}                       (does NOT clear status/tags/shelves)
```

**Bookshelves (user-defined virtual buckets)**
```
GET    /bookshelves                       (list user's shelves with item counts)
POST   /bookshelves                       (body: { name, description? })
GET    /bookshelves/{id}
PATCH  /bookshelves/{id}                  (rename, reorder, edit description)
DELETE /bookshelves/{id}                  (soft-delete; items not affected on other shelves)
GET    /bookshelves/{id}/items?cursor=
POST   /bookshelves/{id}/items            (body: { isbn }; auto-creates user_books anchor)
DELETE /bookshelves/{id}/items/{isbn}
```

**Tags (per-user, cross-cutting)**
```
GET    /tags                              (user's tags with usage count)
POST   /tags                              (body: { name, color? })
PATCH  /tags/{id}                         (rename or recolor)
DELETE /tags/{id}                         (removes tag and all assignments)
GET    /tags/{id}/books?cursor=           (cross-cutting: every book the user has tagged X)
POST   /library/{isbn}/tags               (body: { tag_id }; auto-creates user_books anchor)
DELETE /library/{isbn}/tags/{tag_id}
```

**Reviews**
```
GET    /books/{isbn}/reviews              (public, paginated)
POST   /reviews                           (one per user per book; 409 if exists)
PATCH  /reviews/{id}
DELETE /reviews/{id}
```

**Social (v1 minimal)**
```
POST   /follows/{username}
DELETE /follows/{username}
GET    /users/me/following
GET    /users/me/followers
```

**Import / export** (see "User Data Import" section)
```
GET    /imports/sources                   (list supported sources + schema doc URLs)
POST   /imports                           (multipart upload; ?source=auto|goodreads|storygraph|librarything|bibliobud|generic)
GET    /imports/{job_id}                  (status/progress/counts)
GET    /imports/{job_id}/errors           (per-row error CSV)
DELETE /imports/{job_id}                  (cancel or tombstone)
```

**Capability-gated (future, but reserved now)**
```
GET    /analytics/reading-stats           → 402 if user lacks `capability:analytics`
GET    /analytics/yearly-summary
```

**Meta**
```
GET    /healthz                           (liveness)
GET    /readyz                            (DB ping + auth provider check)
GET    /api/v1/openapi.yaml               (the bundled spec, served from embedded FS)
```

### HTML routes (HTMX, `/`)

Mirror the resource layout but return Templ-rendered fragments. Not part of the public API contract — free to evolve. Examples: `GET /library`, `POST /library/copies` (returns `<tr>` fragment), `GET /lists/{id}` (full page or fragment depending on `HX-Request` header).

## Book Metadata Sourcing

**Principle: lazy and on-demand.** The `books` table is never bulk-seeded from a third-party dump. Books enter the cache only when a user looks them up (ISBN scan, search, or import). This keeps the self-host footprint tiny, avoids licensing-data shipping issues, and means metadata is always fetched against current upstream data.

**Provider abstraction:**
```go
type BookMetadataProvider interface {
    Name() string                                              // "open_library" | "isbndb" | ...
    LookupByISBN(ctx context.Context, isbn string) (*domain.Book, error)
    Search(ctx context.Context, q SearchQuery) ([]domain.Book, error)
    Capabilities() ProviderCapabilities                        // supports search? cover images?
}
```

Two concrete impls at v1: `openlibrary` (free, default, always-on), `isbndb` (paid, optional via API key). New sources (Google Books, BNB, etc.) drop in by implementing the interface.

**Resolver chain** (`internal/books/resolver.go`):
- Priority order configured via env: `BIBLIOBUD_BOOK_PROVIDERS=openlibrary,isbndb` (left = first tried).
- `LookupByISBN(isbn)`:
  1. Check `books` table. Hit → return (and async-refresh if `fetched_at` > 30 days old).
  2. Check negative cache table `book_lookup_misses` (TTL 24h). Hit → return 404 immediately, no upstream call.
  3. Walk providers in order; first non-error result wins. Persist to `books` with `source` and `source_id`.
  4. All providers exhausted → write to `book_lookup_misses`, return 404.
- `Search(query)`:
  1. Query local `books` full-text index first.
  2. If results < threshold (e.g. 5) OR caller passes `?fresh=true`, fan out to providers in parallel with timeout.
  3. Merge/dedupe by ISBN; new entries persisted asynchronously (search returns immediately, persistence happens in a goroutine with bounded queue).
- **Per-provider rate limiting**: token bucket per provider name (Open Library asks for ≤100 req/5min; ISBNdb has a paid quota). On 429/5xx from upstream, mark provider unhealthy for a cooldown window.
- **`POST /books/refresh/{isbn}`**: bypasses cache and negative cache, forces re-fetch. Capability-gated to prevent abuse (`capability:metadata_refresh` — free for self-host, free tier in hosted, but rate-limited per user).

**`books` schema additions** to support this:
```
books.source           ('open_library' | 'isbndb' | 'manual' | 'imported')
books.source_id        (provider's stable ID, e.g. OL works key)
books.fetched_at       (last successful upstream fetch)
books.etag             (optional, if provider supports conditional requests)

book_lookup_misses     (isbn, last_attempted_at, providers_tried[])
                        -- negative cache; periodic GC removes entries > 7 days old
```

**Manual entry**: users can add books not in any provider via `POST /books` (capability-gated to mitigate abuse on hosted; free on self-host). Marked `source='manual'`. Searchable like any other book within that user's instance — but on hosted, manual entries are scoped to the creating user (`books.created_by_user_id` non-null) to avoid one user's typo polluting global search.

## User Data Import

**Principle: zero-friction, multi-source, idempotent.** Importing should be drag-drop-done. The user shouldn't need to know which platform they're migrating from — the server detects.

**Supported sources (v1):**
- **GoodReads** — CSV export (the canonical "Library Export" file)
- **StoryGraph** — CSV export
- **LibraryThing** — CSV/TSV export
- **BiblioBud** — own export format (round-trips for backup/restore + instance migration)
- **Generic CSV** — minimal schema: `isbn,status,rating,shelves,tags,date_read,notes`. Documented in `docs/guides/importing-from-goodreads.md` and friends.

**Importer interface:**
```go
type Importer interface {
    Source() string                                            // "goodreads" | "storygraph" | ...
    Detect(head []byte) (confidence float64)                   // 0.0-1.0; sniff by header columns
    Parse(r io.Reader) (<-chan ImportRecord, <-chan error)
}

type ImportRecord struct {
    ISBN13, ISBN10  string
    Title, Author   string                                     // fallback if no ISBN
    Status          domain.ReadingStatus                       // mapped to wanted/reading/read/dnf
    Rating          *int                                       // 1-5, nullable
    Shelves         []string                                   // → bookshelves (custom only;
                                                               //   reserved names map to status)
    Tags            []string                                   // → tags
    DateRead        *time.Time
    DateAdded       *time.Time
    Notes           string
    OwnedCopy       bool                                       // if true, create a Copy row
    SourceRowNum    int                                        // for error reporting
}
```

**Import flow** (`POST /imports`):
1. User uploads file. Optional `source` query param; if absent, server runs every `Importer.Detect` on the first ~16KB and picks the highest-confidence match. Confidence below 0.5 → 400 with helpful error listing supported sources and the format guides.
2. Server creates an `import_jobs` row (status=`queued`), returns 202 with job ID + polling URL.
3. Worker picks up job, streams parser output into a per-record processor:
   - For each record, resolve `Book` via the resolver chain (lazy fetch). If neither ISBN nor title/author lookup succeeds, write to `import_jobs.errors` with row number and reason; **do not fail the whole job**.
   - Upsert `user_books` anchor with status/rating/dates/notes (last-write-wins on re-import).
   - For each shelf: get-or-create `bookshelf`, insert `bookshelf_item` (idempotent).
   - For each tag: get-or-create `tag`, insert `user_book_tag` (idempotent).
   - If `OwnedCopy`, create a single `Copy` row IF no existing copy with `source='import'` for this `(user, book)` exists (re-import idempotency).
4. Job status transitions: `queued → running → succeeded | failed | partial_success`. `partial_success` is the common case (some unmatched ISBNs).
5. On completion, response includes counts: `{ imported, skipped, failed, books_fetched_from_provider }` and full per-row error list (capped at 1000 entries; rest in downloadable error CSV).

**Idempotency**: re-uploading the same file is safe.
- `user_books` upserts by `(user_id, book_id)`.
- `bookshelf_items`, `user_book_tags`: composite PKs prevent duplicates.
- `copies`: only created if no `source='import'` copy exists for this `(user, book)` — prevents quintupling your library on accident. To force, user can pass `?duplicate_copies=true`.

**Routes:**
```
POST   /imports                    (multipart upload; query: ?source=auto|goodreads|...; returns job)
GET    /imports/{job_id}           (status, progress, counts, error preview)
GET    /imports/{job_id}/errors    (full error CSV download)
DELETE /imports/{job_id}           (cancel if queued/running; tombstones if completed)
GET    /imports/sources            (list of supported sources + their schema docs URLs)
```

**Self-host parity**: every importer ships in the binary. No paid-tier import gating. Hosted free-tier users may have file size limits (e.g. 10MB) — capability-gated via `capability:large_imports`.

## Entitlement Model

```go
type Plan string  // "free" | "pro" | "unlimited" (self-host)
type Capability string  // "analytics" | "unlimited_lists" | "advanced_export" | ...

type Entitlement struct {
    UserID     string
    Plan       Plan
    Status     string  // "active" | "past_due" | "canceled"
    ValidUntil time.Time  // grace period end for past_due
}

type Resolver interface {
    Resolve(ctx context.Context, userID string) (Plan, []Capability, error)
    Invalidate(userID string)  // called from Stripe webhook
}
```

- Self-host: resolver returns `("unlimited", AllCapabilities, nil)` unconditionally.
- Hosted: reads `user_entitlements`, applies grace period (`past_due` keeps capabilities until `valid_until`), maps plan→capabilities via static table.
- Cache: in-memory LRU, 60s TTL, busted by webhook on plan change.
- **Quota checks gate writes only**: if a user downgrades with 47 lists, reads stay open; only `POST /lists` is blocked. Never delete user data on downgrade.

## Auth Flow

**Self-host (`local`):**
1. `POST /auth/signup` → bcrypt password, insert user, mint session, set cookie.
2. `POST /auth/login` → verify password, mint session.
3. Every request: middleware reads cookie or `Authorization: Bearer`, looks up session row, attaches `Principal` to context.

**Hosted (`firebase`):**
1. Client logs in with Firebase SDK, gets ID token.
2. `POST /auth/firebase/exchange` with `{ id_token }` → server verifies once via Firebase Admin SDK, upserts user row keyed on Firebase UID, mints **own opaque session**, returns it. Cookie set if browser.
3. From here on, every request uses the local session — Firebase is not in the hot path.

The `AuthProvider` interface stays small:
```go
type AuthProvider interface {
    ValidateExternal(ctx context.Context, credential string) (ExternalIdentity, error)
}
type LocalAuthProvider interface {
    AuthProvider
    Signup(ctx, email, password) (User, error)
    Authenticate(ctx, email, password) (User, error)
    RequestReset(ctx, email) error
    ConsumeReset(ctx, token, newPassword) error
}
```
Firebase impl returns `ErrUnsupported` for the `LocalAuthProvider` methods; routes for those return 404 in firebase mode.

## Critical Files (to be created)

- `cmd/bibliobud/main.go` — wiring
- `internal/auth/provider.go` — interface + Principal
- `internal/auth/session.go` — DB-backed session store
- `internal/entitlements/resolver.go` — plan→capability resolution + cache
- `internal/entitlements/middleware.go` — `requireCapability`
- `internal/httpapi/errors.go` — RFC 7807 + stable code constants
- `internal/httpapi/pagination.go` — cursor encode/decode
- `internal/storage/repository.go` — repo interfaces
- `internal/domain/models.go` — core types
- `api/openapi.yaml` + `api/paths/*.yaml` + `api/components/schemas/*.yaml`
- `Makefile` — `make api` runs `redocly bundle` → `api/openapi.bundled.yaml`
- Update `README.md` (Chi → net/http)

## Documentation Outline (`docs/`)

```
docs/
  README.md                        -- index
  getting-started/
    self-hosting.md                -- docker run, env vars, first-user bootstrap
    development.md                 -- local dev, make targets, db migrations
  architecture/
    overview.md                    -- this plan, distilled
    auth.md                        -- providers, session lifecycle, threat model
    entitlements.md                -- plans, capabilities, Stripe future
    storage.md                     -- repo interface, sqlite vs postgres tradeoffs
  api/
    overview.md                    -- conventions: auth, errors, pagination, idempotency
    authentication.md              -- both flows with sequence diagrams
    errors.md                      -- RFC 7807 + full code catalog
    rate-limiting.md
    versioning.md                  -- v1 stability promise, deprecation policy
    examples/                      -- curl walkthroughs per resource
    openapi.yaml                   -- symlink or copy of bundled spec
  guides/
    importing-from-goodreads.md
    exporting-your-data.md
    third-party-clients.md         -- AGPL exception explainer + auth recipes
  operations/
    deployment.md
    backup-restore.md
    upgrading.md
  contributing/
    code-style.md
    testing.md
    api-changes.md                 -- how to evolve OpenAPI without breaking clients
```

## Implementation Phase 1: OpenAPI Spec + Documentation

This phase produces the public API contract and the full documentation tree. **No Go code yet.** The spec is what Go handlers will be built against in subsequent phases.

### Files to create

**OpenAPI** (split source, bundleable):
```
api/
  openapi.yaml                              -- root: info, servers, security, $ref into paths/
  paths/
    auth.yaml                               -- /auth/* endpoints
    users.yaml                              -- /users/me, /users/{username}, /users/me/export
    books.yaml                              -- /books/{isbn}, /books/search, /books/refresh/{isbn}
    library.yaml                            -- /library/* endpoints
    copies.yaml                             -- /copies/* endpoints
    bookshelves.yaml                        -- /bookshelves/* endpoints
    tags.yaml                               -- /tags/* + /library/{isbn}/tags
    reviews.yaml                            -- /reviews + /books/{isbn}/reviews
    follows.yaml                            -- /follows/*
    imports.yaml                            -- /imports/*
    analytics.yaml                          -- capability-gated routes (reserved)
    meta.yaml                               -- /healthz, /readyz, /openapi.yaml
  components/
    schemas/
      Book.yaml
      UserBook.yaml
      Copy.yaml
      Bookshelf.yaml
      BookshelfItem.yaml
      Tag.yaml
      Review.yaml
      User.yaml
      Session.yaml
      Plan.yaml                             -- plan + capabilities
      ImportJob.yaml
      Pagination.yaml                       -- shared cursor + envelope
      Problem.yaml                          -- RFC 7807 + extensions (code, capability)
      ErrorCodes.yaml                       -- enum of stable error code strings
    parameters/
      Cursor.yaml
      Limit.yaml
      ISBN.yaml
      IdempotencyKey.yaml
    responses/
      Problem400.yaml                       -- pre-baked RFC 7807 responses
      Problem401.yaml
      Problem402.yaml
      Problem404.yaml
      Problem409.yaml
      Problem410.yaml
      Problem429.yaml
    securitySchemes/
      bearer.yaml                           -- Authorization: Bearer
      cookie.yaml                           -- bb_session cookie
  README.md                                 -- how to bundle, validate, regenerate clients
```

**Documentation** (full tree from outline):
```
docs/
  README.md                                 -- index + nav
  getting-started/
    self-hosting.md                         -- placeholder; quick docker run + env vars
    development.md                          -- placeholder; how to bundle the OpenAPI spec
  architecture/
    overview.md                             -- distilled from this plan
    auth.md                                 -- both flows, sequence diagrams (mermaid)
    entitlements.md                         -- plan→capability model + Stripe future
    storage.md                              -- repo interface, sqlite vs postgres
    book-metadata-sourcing.md               -- resolver chain, providers, negative cache
    user-data-import.md                     -- importer interface, supported sources, idempotency
  api/
    overview.md                             -- conventions hub
    authentication.md                       -- local + firebase flows
    errors.md                               -- RFC 7807, full ErrorCodes catalog
    pagination.md                           -- cursor format + examples
    idempotency.md                          -- Idempotency-Key header semantics
    rate-limiting.md
    versioning.md                           -- v1 stability + deprecation policy
    examples/
      auth.md                               -- curl walkthroughs
      library.md
      bookshelves.md
      tags.md
      imports.md
  guides/
    importing-from-goodreads.md
    importing-from-storygraph.md
    importing-from-librarything.md
    generic-csv-format.md                   -- documents the minimal CSV schema
    exporting-your-data.md
    third-party-clients.md                  -- AGPL exception + auth recipes
  operations/
    deployment.md                           -- placeholder; docker compose example
    backup-restore.md                       -- placeholder
    upgrading.md                            -- placeholder
  contributing/
    code-style.md                           -- placeholder
    testing.md                              -- placeholder
    api-changes.md                          -- how to evolve OpenAPI without breaking clients
```

**Tooling**:
```
Makefile                                    -- targets: api-bundle, api-validate, api-lint, docs-serve
.redocly.yaml                               -- redocly bundle + lint config
```

**Repo updates**:
- `README.md` — Chi → net/http; link to `docs/` and `api/`.

### Scope guards

- All path operations in `api/paths/*.yaml` MUST `$ref` schemas from `components/schemas/*.yaml`. No inline schemas.
- All error responses MUST `$ref` `components/responses/Problem*.yaml`. The `code` field is enum'd against `components/schemas/ErrorCodes.yaml`.
- Each documentation page is a real file — placeholder pages get a one-paragraph intro + a "Status: stub" banner. Empty files are not acceptable; reading a stub should still tell the reader what will go there.
- Every `docs/api/examples/*.md` must use real, valid request/response bodies that match the OpenAPI schemas (so they double as integration test fixtures later).
- `Makefile` `api-validate` target uses `redocly lint`; CI will be wired to this in a later phase.

### Verification (this phase)

1. `make api-bundle` produces `api/openapi.bundled.yaml` with no `$ref` errors.
2. `make api-validate` (redocly lint) reports zero errors. Warnings are acceptable but documented.
3. `oapi-codegen -generate types,client api/openapi.bundled.yaml` produces compilable Go (smoke test only — generated code thrown away this phase).
4. Every doc page renders cleanly in a Markdown previewer; internal links resolve.
5. `docs/README.md` lists every section with one-line descriptions and links.

## Out of Scope (v1)

- Stripe webhook handler & billing UI (entitlement model is in; integration is later)
- Personal access tokens for third-party API clients (auth interface accommodates; impl deferred)
- ETag / If-Match optimistic concurrency
- ActivityPub / federation
- Mobile apps, browser extension (consume the documented API)

## Verification

This is a design plan; "verification" means the implementation phase confirms each decision is workable.

1. **Routing**: scaffold `cmd/bibliobud/main.go` with three routes (`/healthz`, `/api/v1/auth/me`, `/library`) using `net/http` ServeMux; confirm method+path patterns work as intended.
2. **Auth dual-transport**: integration test logs in via JSON (`POST /auth/login`), receives session, then calls `GET /api/v1/users/me` once with `Authorization: Bearer` and once with `Cookie:` — both succeed.
3. **Entitlement no-op in self-host**: with `BIBLIOBUD_MODE=selfhost`, a request to a capability-gated route returns 200; with `BIBLIOBUD_MODE=hosted` and no entitlement, returns 402 with `code: "entitlement.required"`.
4. **OpenAPI bundle**: `make api` produces `openapi.bundled.yaml`; `oapi-codegen` generates a Go client without errors; running the generated client against a local server round-trips a `GET /books/{isbn}` happy path.
5. **Soft-delete + export**: create user, add copies + lists, `DELETE /users/me`, then `GET /users/me/export` from a fresh login window returns 401 (account gone) but the export run *before* deletion contains all data.
6. **GoodReads import (auto-detect)**: upload the canonical GoodReads CSV sample with no `source` param → job auto-detects → reserved shelves map to `user_books.status` (to-read→`wanted`, currently-reading→`reading`, read→`read`), custom shelves materialized as `bookshelves` rows, tags created in user's namespace, `Book` rows backfilled lazily via resolver chain, copies created for items marked owned. Re-upload the same file → no duplicates anywhere.
7. **StoryGraph import**: same flow with a StoryGraph CSV; auto-detect picks the StoryGraph importer; statuses and dates map correctly.
8. **Cross-cutting tag query**: with two books on different shelves both tagged "Gift for Julie", `GET /tags/{id}/books` returns both regardless of shelf membership or status.
9. **Owned-derivation**: create `Copy` for ISBN X → `GET /library/{isbn}` returns `owned: true`; soft-delete the copy → `owned: false`, but anchor row, tags, and shelf membership remain.
10. **Lazy book ingestion**: fresh DB, `GET /books/{isbn}` for an ISBN never seen before → row created with `source='open_library'` and `fetched_at` set; second call hits the cache (no upstream request — verify via test double or request count). 404 ISBN populates `book_lookup_misses` and second call short-circuits.
11. **Provider failover**: with a mocked Open Library returning 503 and ISBNdb configured, lookup falls through to ISBNdb. With both unhealthy, returns 503 (not 404) and the book row is NOT created.
12. **Search merge**: `GET /books/search?q=dune` with empty DB fans out to providers, merges by ISBN, persists results, and returns; subsequent identical search is served from local FTS.
