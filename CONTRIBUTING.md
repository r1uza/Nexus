# Contributing

Run these gates before proposing a change:

```text
dart format --output=none --set-exit-if-changed .
dart analyze
dart run tool/verify.dart
```

Changes to routing, authorization, transport or audit behavior need a negative
contract test as well as a positive test. Never add secrets or payloads to trace
records. Dependencies should be exceptional and justified in the change record.

