# Testing

> **Status: stub.** The full testing guide will land with the Go
> codebase. The shape and standards below are the plan.

## Test categories

- **Unit tests** — fast, in-memory, no I/O. Run on every save.
  Live next to the code (`*_test.go`).
- **Integration tests** — hit a real SQLite or PostgreSQL database
  and exercise repository + service code together. Build tag
  `integration`. Run against **both** SQLite and PostgreSQL in CI.
- **API tests** — spin up the server in-process, drive it with the
  generated OpenAPI client, assert on response shape. These double
  as proof that the implementation matches the spec.
- **Importer fixtures** — every importer (GoodReads, StoryGraph,
  LibraryThing, BiblioBud, generic) ships with a real-world sample
  CSV/JSON under `testdata/` plus the expected post-import state.
  Re-running the importer twice and asserting unchanged state is
  the idempotency check.

## Standards

- **No mocked databases for integration tests.** The whole point is
  to catch divergence between application logic and the actual SQL
  layer. SQLite and PostgreSQL behave differently in subtle ways
  (transaction isolation, datetime handling) — tests must cover
  both.
- **Mock external HTTP** (Open Library, ISBNdb, Firebase, Stripe)
  with `httptest.Server`. Pin payload fixtures in `testdata/`.
- **Time is injectable.** A `Clock` interface gets passed in;
  no test calls `time.Now()` directly.
- **No t.Parallel() unless the test is really parallel-safe.** Most
  database tests aren't.

## What this page will cover

- How to run the fast unit suite vs the full integration suite.
- How to spin up a local PostgreSQL container for integration
  tests.
- How to add a new importer fixture.
- Coverage expectations and what's deliberately not measured.
