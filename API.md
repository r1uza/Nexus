# HTTP API

All responses are JSON. `/healthz` and `/v1/status` are public; every other
route requires `Authorization: Bearer <admin-token>`.

## Dispatch

`POST /v1/dispatch`

```json
{
  "capability": "system.echo",
  "correlationId": "client.request-1",
  "targetNode": "nexus.local",
  "timeoutMs": 5000,
  "payload": {"message": "hello"}
}
```

`targetNode`, `correlationId`, `timeoutMs` and `authorizationTicket` are
optional. `targetNode` becomes mandatory when a capability has multiple
providers. Correlation IDs are accepted once per process lifetime.

## Execution authorization

`POST /v1/authorizations`

```json
{
  "subject": "person.alice",
  "capability": "execute.echo",
  "targetNode": "eco.local",
  "ttlSeconds": 60
}
```

The returned ticket is secret, valid for no more than five minutes and consumed
on first use. Pass it as `authorizationTicket` in the dispatch.

## Register an HTTP node

`POST /v1/nodes`

```json
{
  "id": "service.search",
  "kind": "service",
  "capabilities": ["search.query"],
  "transport": "http",
  "endpoint": "http://127.0.0.1:9000/nexus"
}
```

Remote hostnames must be listed in `NEXUS_ALLOWED_ENDPOINT_HOSTS`. NEXUS.sf
sends a JSON envelope with `protocol`, `correlationId`, `capability`,
`targetNode` and `payload`; the node must return a JSON object with a 2xx status.

