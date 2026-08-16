# NEXUS.sf 1.0.0 release

Status: `OPERATIONAL_LOCAL_CORE`.

Verified on Windows 11 with Dart 3.12.2:

- `dart analyze`: no issues;
- core contract suite: pass;
- HTTP smoke suite: pass;
- CLI demo: pass;
- Windows executable compilation: pass;
- compiled HTTP health and authenticated dispatch: pass;
- artifact checksum verification: pass.

Artifacts are under `dist/`; verify them with `Get-FileHash -Algorithm SHA256`
and compare the result with `dist/SHA256SUMS`.

Docker execution and external production deployment were not verified on the
original audit host. No production deployment is claimed.
