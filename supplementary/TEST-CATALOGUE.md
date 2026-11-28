# Supplementary Task 3.3 test catalogue

The September closure runs covered functionality and initial references for the German, Dutch and Portuguese nodes. This package covers four further elements that the AI-EFFECT proposal lists for Task 3.3 and that the closure runs did not cover:

| Proposal element (T3.3) | Tests in this package |
|---|---|
| (c) Security measures, including access control and verification | SEC-01 to SEC-08 |
| (h) System resilience, data restoration and reboot procedures | RES-01 to RES-07 |
| (g) Data exchange with external AI systems provided by third parties | EXT-01 to EXT-04 |
| (d) User interface and experience | UX-01 and UX-02 |

Three remaining elements depend on partners and are **not** covered here. Each stays BLOCKED with a release condition:

| Element | Release condition | Owner |
|---|---|---|
| (e) Compatibility with Minimum Interoperability Mechanisms | The WP1 MIM specification for AI-EFFECT is supplied | DTU (WP1) |
| (f) Interaction with physical and digital assets through VILLASnode | A retrievable VILLASnode image, or an unchanged build route, containing the chronics hook is supplied | RWTH |
| (g) Portuguese legacy sidecar route | A gRPC-aware adapter or a compatible deployment configuration is supplied | INESC TEC |

## Baselines

| Node | Source | Commit |
|---|---|---|
| Germany, Portugal (overlay) and the platform core | AI-EFFECT `ai-effect-wp3` | `bfe655d6dc58b49dd1e7b09730083971fbf3d29b` |
| Netherlands | `paulban/ai-effect-wp3` fork | `22fbb6eca71265a61bc1f0cee16b6d03f372d554` |
| Portugal TEF services | Partner-supplied `tef-services` source | Fingerprinted by the Portuguese suite workspace marker |

Node code for Germany and Portugal is unchanged between the September baseline `486ccc7` and `bfe655d`; only the orchestrator gained per-node parameters. Before relying on the new baseline, rerun the September node suites' startup and workflow scripts against it (see START-HERE.md).

## Result language

The shared vocabulary from [DEVELOPER-NOTES.md](../DEVELOPER-NOTES.md) applies. This package adds one label:

- `ERROR` — the harness itself failed unexpectedly. It is neither a pass nor a defect; fix the harness and rerun.

## Security (element c)

All security tests are non-destructive. They never print, save or test real credentials; probes use fixed invalid tokens and read-only requests.

| ID | Script | What is checked | Acceptance criterion | Result when not met |
|---|---|---|---|---|
| SEC-01 | 10 | Published host ports and the interface they bind to | Data stores and control endpoints are not published on all interfaces (`0.0.0.0`) | FINDINGS RECORDED per port |
| SEC-02 | 10 | Authentication keys that default to empty in Compose (`${KEY:-}`) | Authentication cannot be switched off silently by an unset variable | DEFECT CONFIRMED |
| SEC-03 | 10, 11 | Privileged mode, added capabilities, host namespaces, Docker socket mounts | None, or justified in the node documentation | FINDINGS RECORDED |
| SEC-04 | 10, 11 | Image provenance: `latest` or untagged images, missing digests | Every pulled image is pinned by tag and its digest is recorded | FINDINGS RECORDED |
| SEC-05 | 11 | Containers running as root | Services run as a non-root user | FINDINGS RECORDED |
| SEC-06 | 11 | Control endpoints probed without a token and with an invalid token | `401` or `403` | DEFECT CONFIRMED |
| SEC-07 | 11 | Data stores reachable from the host without credentials (Redis `PING`, ClickHouse `SELECT 1`, PostgreSQL connection) | Refused or authentication required | DEFECT CONFIRMED |
| SEC-08 | 11 | Workflow service keys stored in the orchestrator's Redis: count and expiry only, never the values | Keys expire after the workflow, or are not stored | DEFECT CONFIRMED |

## Restoration and reboot (element h)

Orchestrator-level tests (RES-01 to RES-04) use the controllable vendor pipeline from EXT-01, so the restart happens while a task is known to be running. They apply to every node, because all nodes share the orchestrator.

| ID | Script | Procedure | Acceptance criterion | Result when not met |
|---|---|---|---|---|
| RES-01 | 21 `-Component Worker` | Restart all orchestrator workers while a 60-second vendor task runs | The workflow completes, or fails explicitly, within the timeout | DEFECT CONFIRMED if it hangs or loses state |
| RES-02 | 21 `-Component Api` | Restart the orchestrator API mid-workflow | Workflow state is still retrievable and the workflow completes | DEFECT CONFIRMED |
| RES-03 | 21 `-Component Redis` | Restart (not recreate) Redis mid-workflow | Workflow state is retained and the workflow completes or fails explicitly | DEFECT CONFIRMED |
| RES-04 | 22 | Recreate the Redis container after a completed workflow (`up --force-recreate`) | The completed workflow is still retrievable | DEFECT CONFIRMED (no persistent state) |
| RES-05 | 23 | Back up each node data volume, restore it into a new test-owned volume, compare file manifests | Identical manifests; backup and restore times recorded | FAIL |
| RES-06 | 24 | Restart policy of every node and core container | `unless-stopped` or `always` for every long-running service | FINDINGS RECORDED |
| RES-07 | 24, then 25 | Record state, restart Docker Desktop (the closest safe stand-in for a host reboot), verify recovery | All long-running containers return healthy, volume manifests unchanged, completed workflows retrievable, a new workflow completes | DEFECT CONFIRMED or FINDINGS RECORDED |

## Third-party AI exchange (element g)

The "vendor" is an independent two-step service built from the platform's own templates and common library at the frozen commit, exactly as an outside AI provider would onboard:

- `vendor_ingest` (sequential template) reads any `inline`, `http` or `file` DataReference and records its SHA-256, size and record count.
- `vendor_model` (concurrent template) fits a simple per-column baseline model and writes predictions with provenance. Its model is a stand-in; the tests judge the exchange, not model quality.

| ID | Script | Procedure | Acceptance criterion | Result when not met |
|---|---|---|---|---|
| EXT-01 | 20 | Build the vendor use case from templates, generate the onboarding export, start the services | Export generated; services healthy; authentication enforced with the service key | BLOCKED or FAIL |
| EXT-02 | 30 `-Node <name>` | Pass a node workflow's output reference to the vendor pipeline; the harness independently reads the same data | Vendor SHA-256 equals the harness SHA-256; record counts match; vendor output carries the source workflow ID | FAIL |
| EXT-03 | 31 | Run overlapping vendor workflows with distinct marker inputs | Every output carries its own workflow's marker. Each workflow is classified as `ok`, `exchanged` or `failed` | DEFECT CONFIRMED (template-level regression of DK-REL-02) |
| EXT-04 | 30 `-NegativeCases` | Unsupported protocol, missing file and malformed content sent to the vendor pipeline | Explicit failure with no output | FAIL |

## User interface and experience (element d)

| ID | Script | Procedure | Acceptance criterion |
|---|---|---|---|
| UX-01 | 40 | Heuristic evaluation by 3 to 5 evaluators, each working alone, on each in-scope interface (see UX-EVALUATION-PROTOCOL.md) | Every evaluator completes all ten heuristics for each interface |
| UX-02 | 41 | Aggregate the evaluations | Report problems with severity 3 or 4, how many evaluators found each, and mean severity per heuristic. `FINDINGS RECORDED` |

## Evidence boundary

These tests are bounded technical checks on a local Docker deployment. They do not establish penetration resistance, behaviour on the hosted platform, full host or hardware failure recovery, production service levels or Task 3.4 scalability. The UX evaluation is an expert inspection, not a representative user study.
