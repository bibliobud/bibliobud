# Architecture overview

BiblioBud is a single Go binary that runs in two modes:

- **Hosted** (`BIBLIOBUD_MODE=hosted`) — multi-tenant SaaS. Auth via
  Firebase. Paid features gated per-user via Stripe (future).
- **Self-hosted** (`BIBLIOBUD_MODE=selfhost`) — single Docker container.
  Built-in password auth. Every user has every feature with no billing.

Both modes share one codebase. Mode-specific behavior is encapsulated
behind interfaces (`AuthProvider`, `EntitlementResolver`) so the rest of
the code is mode-agnostic.

## High-level diagram

```
                       ┌───────────────────────────────┐
   browser  ─────────► │  /                            │   Templ + HTMX
                       │  HTML handlers                │   fragments
                       │  (internal/web)               │
                       └──────────────┬────────────────┘
                                      │ shared service layer
                                      │
   third-party        ┌───────────────▼────────────────┐
   client    ────────►│  /api/v1/                      │   JSON
                      │  JSON handlers                 │   contract
                      │  (internal/httpapi)            │
                      └──────────────┬─────────────────┘
                                     │
                ┌────────────────────┼────────────────────────────┐
                │                    │                            │
        ┌───────▼──────┐  ┌──────────▼─────────┐  ┌───────────────▼────────┐
        │ AuthProvider │  │ EntitlementResolver│  │ Service layer          │
        │ (interface)  │  │ (interface)        │  │ books, library, copies,│
        │              │  │                    │  │ shelves, tags, reviews │
        │ firebase /   │  │ self-host: noop    │  │ imports, exports       │
        │ local        │  │ hosted: db + cache │  │                        │
        └──────────────┘  └────────────────────┘  └───────────────┬────────┘
                                                                  │
                                                  ┌───────────────▼────────┐
                                                  │ Repository (interface) │
                                                  │ sqlite / postgres      │
                                                  └────────────────────────┘
```

## Stack

- **Go** with `net/http` (Go 1.22+ ServeMux) and `slog` — built-ins by
  default. No router framework.
- **Templ + HTMX + Alpine.js + Tailwind** — server-rendered HTML.
- **SQLite or Postgres** — same code; selected by config.
- **OpenAPI 3.0.3** — the JSON API is contract-first. The bundled spec
  is embedded in the binary and served at `/api/v1/openapi.yaml`.
- **Single Docker image** — the binary embeds templates, static assets,
  and the OpenAPI spec.

## Two route trees

The HTML side (`/`) and JSON side (`/api/v1/`) are separate handler
packages that share the service layer.

- HTML handlers return `text/html`. They are not part of the public API
  contract — handler URLs and shapes can change freely.
- JSON handlers return `application/json` or `application/problem+json`.
  These are versioned and stable; breaking changes ship a new version
  prefix.

The split keeps the JSON API clean (no HTMX-specific weirdness in the
public contract) while letting the HTML handlers stay coupled to the
UI's needs (returning fragments, conditional layouts based on
`HX-Request`, etc).

## Domain model in one paragraph

A `Book` is canonical metadata, one row per ISBN, shared across every
user on the instance. A `UserBook` row anchors the user's relationship
to a book — reading status (wanted / reading / read / dnf / null),
rating, dates, notes. A `Copy` is a physical (or digital) instance the
user owns; multiple copies per book are allowed. "Owned" is derived
from copy existence, not a status. `Bookshelves` are user-defined
virtual buckets (no system shelves). `Tags` are per-user, cross-cutting
labels on the user-book relationship — independent of shelves and
status. See [storage.md](storage.md) for the schema.

## Key design decisions

- **Lazy book metadata.** The `books` table is never bulk-seeded.
  Books enter the cache only when a user looks them up. See
  [book-metadata-sourcing.md](book-metadata-sourcing.md).
- **Pluggable auth.** A small `AuthProvider` interface with two
  implementations. The session token lives in our database — Firebase
  is consulted only at exchange time. See [auth.md](auth.md).
- **Plan-based entitlements.** Capabilities are a function of the
  user's plan. Self-host hardcodes `plan=unlimited`. Stripe (future)
  mutates plan, never capabilities directly. See
  [entitlements.md](entitlements.md).
- **Soft delete with 30-day retention.** Deletes return 410 for 30
  days, then 404. GDPR export endpoint reads through soft-deletes for
  the requesting user.

## What lives where

```
cmd/bibliobud/main.go              entry, config, wiring
internal/
  domain/                          pure types
  auth/                            providers + sessions
  entitlements/                    resolver + middleware
  books/                           canonical metadata + provider chain
  library/                         user-book anchor service
  copies/                          physical-instance CRUD
  bookshelves/                     shelf service
  tags/                            tag service + cross-cutting query
  reviews/                         review service
  imports/                         multi-source data import
  exports/                         GDPR export
  storage/                         sqlite / postgres impls
  httpapi/                         JSON handlers (consumes OpenAPI types)
  web/                             HTML handlers + Templ
api/                               OpenAPI 3.0.3 split source
docs/                              this directory
```
