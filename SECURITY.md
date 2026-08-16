# Security

## Supported version

Security fixes are applied to the current `1.x` line.

## Defaults

- loopback bind only;
- authenticated control plane;
- non-loopback startup refused without an explicit 32+ character token;
- 1 MiB request and response limits;
- five-second dispatch timeout;
- no redirect following for HTTP nodes;
- endpoint hostname allowlist;
- one-use, capability-bound execution tickets;
- payload-free traces;
- no implicit provider selection.

Use TLS termination in front of NEXUS.sf for any network deployment. Rotate the
admin token through the process environment or a secret manager; never commit
it. Restrict `NEXUS_ALLOWED_ENDPOINT_HOSTS` to exact service names you operate.

## Reporting

Do not open a public issue for a suspected vulnerability. Send a minimal report
to the private security contact configured by the operator of your distribution.
This source snapshot intentionally contains no fictional email address.

