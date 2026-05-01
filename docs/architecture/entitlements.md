# Entitlements

The entitlement system answers: "is this user allowed to use this
feature?" In hosted mode the answer depends on a Stripe subscription;
in self-host mode the answer is always yes. The rest of the codebase
is mode-agnostic.

## Plans and capabilities

```go
type Plan string  // "free" | "pro" | "unlimited"

type Capability string
const (
    CapAnalytics         Capability = "analytics"
    CapMetadataRefresh   Capability = "metadata_refresh"
    CapLargeImports      Capability = "large_imports"
    CapManualBookEntry   Capability = "manual_book_entry"
    // ... extended over time
)
```

A `Plan` maps to a fixed set of `Capability`. The mapping is a static
table inside the binary — never read from the database, never set
directly by Stripe. **Stripe webhooks mutate plan, not capabilities.**

This indirection is the whole point: the day product decides "analytics
moves into the free tier," it's a one-line code change to the plan
table — no database backfill, no Stripe schema change, no per-user
update.

| Plan        | Capabilities |
|-------------|--------------|
| free        | (baseline) |
| pro         | analytics, metadata_refresh, large_imports |
| unlimited   | every capability (self-host default) |

## Resolver

```go
type Resolver interface {
    // Returns the user's current plan, status, and the set of
    // capabilities that plan grants right now (with grace-period logic
    // applied).
    Resolve(ctx context.Context, userID string) (Plan, Status, []Capability, error)
    // Called from the Stripe webhook to bust the cache for one user.
    Invalidate(userID string)
}
```

Two implementations:

- `selfhost.Resolver` returns `(unlimited, active, allCapabilities, nil)`
  unconditionally. No DB hit.
- `hosted.Resolver` reads `user_entitlements`, applies grace-period
  rules, maps plan → capabilities. Cached.

### Caching

In-memory LRU keyed by user ID, 60s TTL, ~10k entry capacity. A Stripe
webhook handler calls `Invalidate(userID)` on plan change. Cache is
process-local — multi-replica deployments rely on the 60s TTL for
eventual consistency, which is acceptable for entitlements because
the spread is at most one minute and capability checks are lenient
(they only block writes; see below).

### Grace periods

A user whose Stripe charge fails is in `status: past_due`. We do **not**
strip their capabilities at the moment of failure — that creates a
terrible UX where a user mid-session suddenly hits 402 errors. Instead:

- `past_due` retains all current capabilities until `valid_until`
  (typically the end of the current billing cycle).
- `canceled` retains capabilities until `valid_until` then drops to the
  `free` plan's capability set.
- The resolver returns `(plan, status, capabilities)` — clients can
  surface the warning ("payment failed, capabilities expire on …")
  while still functioning normally.

## Middleware

```go
mux.HandleFunc("GET /api/v1/analytics/reading-stats",
    requireCapability(CapAnalytics, analyticsHandler))
```

`requireCapability` is a thin middleware:

1. Read `Principal` from request context.
2. Resolve the user's capabilities.
3. If the capability is present, hand off to the handler.
4. If not, write a 402 RFC 7807 problem with `code: entitlement.required`
   and `capability: <name>`.

In `selfhost.Resolver`, every capability resolves true → middleware is
a no-op.

## Quota gating: writes only

Some capabilities aren't binary "you may call this endpoint" — they're
quotas. For example, hypothetically the free tier might cap users at
10 bookshelves. The rule:

> **Quota checks gate writes only. They never invalidate existing data.**

If a `pro` user with 47 bookshelves downgrades to `free` (cap: 10):

- Their existing 47 shelves are NOT deleted.
- `GET /bookshelves` still returns all 47.
- `POST /bookshelves` returns 402 `entitlement.quota_exceeded`.

This avoids the surprise-data-loss anti-pattern. The product decision
of how to nudge users back to a paid tier (banners, opt-in shelf
archival) is UX, not API.

## Stripe integration (future)

Out of scope for v1, but the entitlement model is shaped to receive it:

```
Stripe Checkout → user subscribes
       │
       ▼
Stripe Webhook (customer.subscription.{created,updated,deleted})
       │
       ▼
internal/entitlements/webhook.go
   - verify signature
   - upsert user_entitlements (plan, status, valid_until, stripe_*_id)
   - resolver.Invalidate(userID)
   - audit log
```

Plan changes are eventually consistent (60s cache TTL on other replicas,
instant on the replica that processed the webhook). This is acceptable
because:

1. Capability changes downward are rare (cancellations) and gated by
   `valid_until` anyway.
2. Capability changes upward (upgrades) take effect within a minute,
   which matches user expectation post-checkout.

## Why not entitlements-as-rows?

Earlier drafts had a `user_entitlements` table with one row per
(user, capability). That model has problems:

- Adding a capability requires a backfill migration ("everyone with
  pro gets this new capability").
- Stripe doesn't think in capabilities, it thinks in subscriptions.
  Bridging the two creates synchronization bugs.
- The plan→capability table has product semantics that belong in code,
  not data — the right place to change "what does pro get?" is a code
  review, not a runtime config flag.

Plan-as-data, capabilities-as-code is the simpler, less error-prone
shape.
