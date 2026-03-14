# BiblioBud

A self-hostable book tracking app. Scan barcodes, organize your library, import from GoodReads. Built with Go, HTMX, and PostgreSQL.

**Status: Early development.** Core features are being built. 

## What is this?

BiblioBud is an open source alternative to GoodReads that you can host yourself or use at [bibliobud.com](https://bibliobud.com) (coming soon).

- **Scan a barcode** — open the app in a bookstore, scan the ISBN, instantly see the book and add it to your library
- **Organize with lists and tags** — create as many lists as you want, tag books however you like, and put the same book in multiple lists
- **Import from GoodReads** — upload your GoodReads CSV export and your entire library transfers over, shelves and all
- **Book clubs and social features** — reviews, public lists, follow other readers, and start book clubs (coming later)
- **Self-host for free** — run the same code we run, with every feature enabled, on your own server

## Tech stack

Go · [Chi](https://github.com/go-chi/chi) · [Templ](https://templ.guide/) · [HTMX](https://htmx.org/) · [Alpine.js](https://alpinejs.dev/) · [Tailwind CSS](https://tailwindcss.com/) · PostgreSQL · [sqlc](https://sqlc.dev/) · Caddy

## License

[AGPL-3.0](LICENSE)

Software that communicates with BiblioBud via its REST API (browser extensions, mobile apps, plugins) is not considered a derivative work and may use any license.