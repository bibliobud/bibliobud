# Deployment

> **Status: stub.** The server isn't built yet. This page will hold
> the canonical deployment recipes (Docker / Docker Compose,
> systemd, Kubernetes manifest, reverse-proxy snippets) once the
> binary exists.

## Intended deployment shapes

- **Docker single-container.** The reference path. Bind-mount a
  data volume; everything (DB, sessions, uploads) lives inside.
- **Docker Compose with PostgreSQL.** For multi-user instances
  expecting more than a few hundred users — point
  `BIBLIOBUD_DB_URL` at the `postgres://` endpoint instead of the
  default SQLite file.
- **Bare binary + systemd.** A statically linked Go binary; works
  fine.
- **Behind Caddy / nginx / Traefik.** TLS termination at the
  reverse proxy. Caddy's auto-TLS is the recommended path for a
  one-host install.

## What this page will cover

- A copy-pasteable `docker-compose.yml`.
- A reference Caddyfile.
- Recommended file system layout for the data volume.
- Sizing / resource notes (RAM and disk per N users).
- Health-check probes for orchestrators.
- TLS, CORS, and cookie scope considerations.

For now, see
[getting-started/self-hosting.md](../getting-started/self-hosting.md)
for the planned environment variable surface.
