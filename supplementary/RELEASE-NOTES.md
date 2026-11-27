# Supplementary package release notes

## v0.1 - 27 November 2026 (pre-release, not yet executed)

- Added the cross-node supplementary package for the Task 3.3 elements the September closure runs did not cover:
    - security: SEC-01 to SEC-08;
    - restoration and reboot: RES-01 to RES-07;
    - third-party AI exchange: EXT-01 to EXT-04;
    - user interface and experience: UX-01 and UX-02.
- Baselines:
    - German, Portuguese and platform core at AI-EFFECT `bfe655d6dc58b49dd1e7b09730083971fbf3d29b`;
    - Dutch node at fork commit `22fbb6eca71265a61bc1f0cee16b6d03f372d554`.
- Added a stand-in third-party vendor, built at run time from the platform's sequential and concurrent templates and common library. The provenance hashes of the copied template files are recorded in the vendor workspace marker.
- Added the `ERROR` result label for harness failures.
- Validation so far:
    - all scripts pass the Windows PowerShell 5.1 parser;
    - the vendor services were exercised in memory against the platform's template handlers;
    - the probe answered 401 for missing and invalid tokens and 422 for a valid one;
    - invalid references failed explicitly;
    - two tasks with the same ID collided in the concurrent template, the mechanism behind DK-REL-02.
- Partner-dependent elements remain BLOCKED with release conditions: MIM compatibility (DTU), VILLASnode (RWTH) and the Portuguese legacy sidecar (INESC TEC).
