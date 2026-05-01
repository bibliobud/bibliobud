# Examples — Auth

End-to-end curl walkthroughs for the auth endpoints. Replace
`example.com` with your instance hostname.

## Sign up (local mode)

```bash
curl -X POST https://example.com/api/v1/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{
    "email": "alice@example.com",
    "username": "alice",
    "password": "correct horse battery staple",
    "display_name": "Alice"
  }'
```

```http
HTTP/1.1 201 Created
Content-Type: application/json
Set-Cookie: bb_session=bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d; HttpOnly; Secure; SameSite=Lax

{
  "token": "bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d",
  "expires_at": "2026-05-30T15:32:18Z",
  "user": {
    "id": "01HQNRC2YHM0D8J7K3WF8XB5VP",
    "username": "alice",
    "email": "alice@example.com",
    "display_name": "Alice"
  }
}
```

## Log in (local mode)

```bash
curl -X POST https://example.com/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{
    "identifier": "alice@example.com",
    "password": "correct horse battery staple"
  }'
```

`identifier` accepts either email or username.

## Exchange a Firebase ID token (firebase mode)

```bash
curl -X POST https://bibliobud.com/api/v1/auth/firebase/exchange \
  -H 'Content-Type: application/json' \
  -d '{ "id_token": "eyJhbGciOi..." }'
```

Response is identical to local-mode login. From here on, use the
returned BiblioBud session token, **not** the Firebase ID token.

## Inspect the current session

```bash
TOKEN=bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d

curl https://example.com/api/v1/auth/me \
  -H "Authorization: Bearer $TOKEN"
```

```json
{
  "user": {
    "id": "01HQNRC2YHM0D8J7K3WF8XB5VP",
    "username": "alice",
    "email": "alice@example.com",
    "display_name": "Alice"
  },
  "plan": {
    "plan": "pro",
    "status": "active",
    "valid_until": null,
    "capabilities": ["analytics", "metadata_refresh", "large_imports"]
  }
}
```

## Log out

```bash
curl -X POST https://example.com/api/v1/auth/logout \
  -H "Authorization: Bearer $TOKEN"
```

```http
HTTP/1.1 204 No Content
Set-Cookie: bb_session=; Max-Age=0
```

## Password reset

```bash
# Step 1 — request a reset email
curl -X POST https://example.com/api/v1/auth/password/reset/request \
  -H 'Content-Type: application/json' \
  -d '{ "email": "alice@example.com" }'

# 204 No Content (always — we don't leak account existence)

# Step 2 — consume the token from the email
curl -X POST https://example.com/api/v1/auth/password/reset/confirm \
  -H 'Content-Type: application/json' \
  -d '{
    "token": "rt_d3a8f2c4e1b6...",
    "new_password": "new correct horse battery staple"
  }'
```

A successful reset returns 204 and **revokes every existing session**
for the user.

## Wrong password

```bash
curl -X POST https://example.com/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{ "identifier": "alice@example.com", "password": "wrong" }'
```

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/problem+json

{
  "type": "https://bibliobud.com/errors/auth-invalid-credentials",
  "title": "Invalid credentials",
  "status": 401,
  "code": "auth.invalid_credentials"
}
```

We deliberately conflate "wrong password" and "no such account" to
avoid leaking which emails are registered.
