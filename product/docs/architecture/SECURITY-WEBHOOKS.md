# Webhook Security

> External events can affect leakage math. They must be authenticated and replay-safe.

---

## Current Code Reality

`automation_connection.webhook_url` supports outbound snapshot pushes.
Inbound runtime webhook authentication is not yet defined in docs.

---

## Required Controls

| Control | Purpose |
|---|---|
| Per-map or per-architecture webhook secret | Authenticate sender |
| Signature header | Verify payload was not modified |
| Timestamp header | Prevent replay attacks |
| Idempotency key | Prevent duplicate retries from double-counting |
| Source allowlist | Optional extra protection for known systems |
| Rate limit | Protect solo-operator accounts from runaway automations |

---

## Minimum Header Contract

```text
X-Emgram-Signature: hmac_sha256(payload, secret)
X-Emgram-Timestamp: 2026-06-12T14:22:00Z
X-Emgram-Idempotency-Key: job-9981:s2:complete:v1
```
