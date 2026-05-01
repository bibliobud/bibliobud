# Code style

> **Status: stub.** Detailed conventions will be written as the Go
> codebase lands. The high-level principles below are the bar.

## Principles

- **Standard library by default.** `net/http` over Chi, `database/sql`
  + `sqlc` over an ORM, `log/slog` over third-party loggers. Bring
  in dependencies when they pull weight.
- **No clever indirection.** Interfaces exist where we have at least
  two implementations or a real test seam. Don't wrap things "in
  case we want to swap them later."
- **Errors carry context, not stack traces.** `fmt.Errorf("loading
  user %s: %w", id, err)`. Stable error sentinels for control flow;
  `errors.Is` / `errors.As` for matching.
- **Small packages over deep ones.** A package is a unit of API. If
  a package's exported surface drifts past ~10 names, split.
- **Tests live next to code.** `_test.go` in the same package for
  unit, `_integration_test.go` with a build tag for tests that hit
  the database.

## Tooling

- `gofmt` (enforced).
- `go vet` (enforced).
- `staticcheck` (enforced).
- `golangci-lint` configuration TBD; the bar will be "no new
  warnings, fix-or-explain existing ones."

## What this page will cover

- Package layout (mirrors `internal/<domain>/`).
- Repository / service / handler responsibilities and seams.
- Logging and structured-log field conventions.
- HTTP handler patterns (request decoding, error response
  construction, validation placement).
- Templ component conventions for the HTMX layer.
- SQL style and migration discipline (`sqlc`-friendly).
