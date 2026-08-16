# NEXUS.sf

NEXUS.sf is the operational, open-core edition of the SF connection and
coordination fabric. It turns the contract-only NEXUS baseline into a runnable
Dart service while retaining its central invariants:

- coordination does not create authority;
- routing is exact and ambiguous routes fail closed;
- `execute.*` capabilities require a short-lived, one-use authorization;
- traces contain operational metadata, never request or response payloads;
- remote endpoints are denied unless their hostname is explicitly allowlisted.

The Apache-2.0 core has no third-party runtime dependencies.

## Quick start

Requirements: Dart 3.6 or newer.

```powershell
dart pub get
dart run bin/nexus_sf.dart doctor
dart run bin/nexus_sf.dart demo
dart run bin/nexus_sf.dart serve
```

The server binds to `127.0.0.1:8787`. If `NEXUS_ADMIN_TOKEN` is not set, a
temporary admin token is generated and printed. A token is mandatory for any
non-loopback bind.

```powershell
$env:NEXUS_ADMIN_TOKEN = 'replace-with-at-least-32-random-characters'
dart run bin/nexus_sf.dart serve --port 8787
```

Health is public:

```text
GET /healthz
GET /v1/status
```

Control-plane routes require `Authorization: Bearer <token>`:

```text
GET    /v1/nodes
GET    /v1/traces?limit=100
POST   /v1/nodes
DELETE /v1/nodes/{id}
POST   /v1/authorizations
POST   /v1/dispatch
```

Example dispatch:

```powershell
$headers = @{ Authorization = 'Bearer replace-with-at-least-32-random-characters' }
$body = @{ capability = 'system.echo'; payload = @{ message = 'ciao' } } | ConvertTo-Json
Invoke-RestMethod http://127.0.0.1:8787/v1/dispatch -Method Post -Headers $headers -ContentType application/json -Body $body
```

For an `execute.*` capability, issue a capability- and target-bound ticket,
then spend it exactly once:

```powershell
$ticketBody = @{ subject = 'operator.alice'; capability = 'execute.echo'; targetNode = 'eco.local'; ttlSeconds = 60 } | ConvertTo-Json
$ticket = Invoke-RestMethod http://127.0.0.1:8787/v1/authorizations -Method Post -Headers $headers -ContentType application/json -Body $ticketBody
$dispatchBody = @{ capability = 'execute.echo'; targetNode = 'eco.local'; authorizationTicket = $ticket.ticket; payload = @{ operation = 'harmless-echo' } } | ConvertTo-Json
Invoke-RestMethod http://127.0.0.1:8787/v1/dispatch -Method Post -Headers $headers -ContentType application/json -Body $dispatchBody
```

## Verification

```powershell
dart analyze
dart run tool/verify.dart
dart compile exe bin/nexus_sf.dart -o build/nexus-sf.exe
```

`tool/verify.dart` runs the core contracts, HTTP smoke test and CLI demo. See
[`API.md`](API.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), [`AUDIT.md`](AUDIT.md),
[`OPEN_CORE.md`](OPEN_CORE.md), and [`SECURITY.md`](SECURITY.md) for the public
contracts, design, audit, edition boundary, and security guidance.

## Docker

```powershell
docker compose up --build
```

The container exposes port `8787`. Set `NEXUS_ADMIN_TOKEN` and
`NEXUS_ALLOWED_ENDPOINT_HOSTS` through the environment; do not put secrets in
the compose file or source tree.

The ready-to-run Windows executable and source archive are in [`dist/`](dist/).

## Built-in nodes

| Node | Role | Capability |
|---|---|---|
| `nexus.local` | service | `system.echo` |
| `uvo.local` | interface | `interface.echo` |
| `ugai.local` | intelligence | `intelligence.echo` |
| `eve.local` | verifier | `verify.payload` |
| `eco.local` | operator | `execute.echo` |

HTTP nodes can be registered at runtime. NEXUS.sf forwards a normalized JSON
envelope to the registered endpoint and returns its JSON response.

## Open-core boundary and limitations

Everything in this repository is Apache-2.0 open core. SSO/SAML/OIDC,
enterprise RBAC, multi-tenant isolation, distributed consensus and high
availability, managed persistence, signed policy distribution, compliance
reporting, fleet management, and commercial support remain outside this core.

The current release is a local operational core. It does not claim external
production deployment, high availability, certification, or compliance, and
it does not provide durable distributed state or enterprise identity.

## Status

`1.0.0 / OPERATIONAL_LOCAL_CORE`. This means the local runtime, HTTP adapter,
security gates and tests are executable. It does not claim an external
production deployment, high availability, or certification.
