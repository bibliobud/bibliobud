# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in BiblioBud, please report it
responsibly. **Do not open a public GitHub issue.**

Use GitHub's private vulnerability reporting:

1. Go to the [Security tab](https://github.com/bibliobud/bibliobud/security)
2. Click **"Report a vulnerability"**
3. Describe the issue, including steps to reproduce if possible

You will receive a response within 72 hours. We will work with you to
understand the issue and coordinate a fix before any public disclosure.

## What qualifies as a security issue

- Authentication or authorization bypasses
- SQL injection, XSS, or other injection attacks
- Exposure of user data or secrets
- Vulnerabilities in dependencies that affect BiblioBud

## What does not qualify

- Issues in third-party services (Stripe, Firebase, Open Library)
- Denial of service on self-hosted instances (that's the operator's concern)
- Feature requests or general bugs (use GitHub Issues for these)

## Supported versions

Security fixes are applied to the latest release only. We recommend
always running the most recent version.
