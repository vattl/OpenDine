# WI-080 remediation: Java bootstrap tests

- Git head: `afe877d104b6450d6d2e1c5d4ca71b714b2ffe65`
- Observed at: `2026-11-02 06:34:52 +08:00`
- Runtime: Temurin OpenJDK `1.8.0_504`
- Command: `mvn -B -Pprod -Dtest=FreshInstallBootstrapTest test`
- Exit code: `0`
- Result: `Tests run: 6, Failures: 0, Errors: 0, Skipped: 0`
- Maven result: `BUILD SUCCESS`

This record contains no credentials or connection strings. The command was executed after the network-segmentation and immutable-image remediation had been amended into the exact Git head above.
