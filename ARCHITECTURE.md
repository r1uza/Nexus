# Architecture

NEXUS.sf is a small control-plane service around five independent boundaries:

```text
HTTP / CLI ingress
        |
        v
schema + auth + size limits
        |
        v
exact capability registry -----> one-use execute authorization
        |
        v
local handler | allowlisted HTTP adapter
        |
        v
payload-free trace + JSONL audit
```

## Routing

A dispatch may name a target node. Without a target, exactly one enabled node
must advertise the requested capability. Zero matches returns `route_not_found`;
more than one returns `route_ambiguous`. Registration order never selects a
winner.

## Authority

NEXUS.sf never mints authority from node identity, routing, transport success or
an EVE verdict. An authenticated administrator can issue a ticket bound to:

- subject;
- exact `execute.*` capability;
- optional exact target node;
- expiration (maximum five minutes);
- cryptographically random ticket identifier.

The ticket is consumed atomically before handler invocation and cannot be
replayed, including after a downstream failure.

## Transport

The local transport invokes explicitly registered handlers. The HTTP transport
accepts only `http` or `https` endpoints and only loopback or configured exact
hostnames. Redirect following is disabled. Requests and responses are bounded.

## Persistence and observability

The core persists append-only traces to `traces.jsonl`. Trace records contain
IDs, route, outcome, timing and error code. Payloads and authorization tickets
are deliberately excluded. The in-memory trace window supports the API; the
JSONL log provides restart-independent evidence.

## Extension points

The public Dart library exposes transport, trace and clock contracts so an
edition or downstream distribution can add a broker, database or policy engine
without weakening the core routing and authorization behavior.

