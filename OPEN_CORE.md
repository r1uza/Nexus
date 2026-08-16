# Open-core boundary

Everything committed in this repository is the open core and is licensed under
Apache License 2.0.

## Included

- CLI and HTTP service;
- exact registry and deterministic routing;
- local and allowlisted HTTP transports;
- payload-free audit trail;
- one-use authorization tickets for operator capabilities;
- UVO, UGAI, EVE and ECO local demonstration adapters;
- tests, Docker packaging and operational documentation;
- stable Dart extension contracts.

## Explicitly outside this repository

Commercial or organization-specific editions may provide SSO/SAML/OIDC, RBAC,
multi-tenant isolation, distributed consensus, managed databases, message
brokers, fleet management, signed policy distribution, compliance reporting and
support SLAs. None of those features is required to run or extend the core.

An edition must not silently bypass the core invariants. In particular, it must
not convert identity, routing, verification or transport success into execution
authority.

