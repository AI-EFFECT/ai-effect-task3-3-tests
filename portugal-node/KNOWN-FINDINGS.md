# Known findings and how to interpret them

The table below is the current position for the frozen baseline `486ccc702bb2afca79fb7d31258d62ee0f94dbfc`.

| ID | Finding | Evidence from the recorded run | Impact | Owner action |
|---|---|---|---|---|
| PT-CFG-01 | Knowledge Store is healthy as an application, but the supplied Compose health check uses `curl` on `/`. The image has no `curl` and the service exposes `/health`. | Script 03: `/health`, `/docs` and `/openapi.json` returned 200. | Docker reports the supplied configuration unhealthy even though the service is available. | Update the official health check to a command available in the image and to `/health`. |
| PT-CFG-02 | Synthetic Data is available, but its supplied Compose health check calls the undefined root path `/`. | Script 04: `/docs`, `/openapi.json` and `/models` returned 200; `/` returned 404. | Docker reports the supplied configuration unhealthy while the API is available. | Update the official health check to a documented route such as `/openapi.json`, or add a dedicated health endpoint. |
| PT-SC-01 | The legacy Data Provision container runs gRPC on port 50051. The supplied sidecar Compose and adapter settings expect HTTP on port 600. | Script 31 records the service log and effective Compose configuration. | The legacy-sidecar workflow cannot be run against the supplied combination. The integrated Portugal route is not affected. | Provide an approved gRPC-aware adapter, or a compatible official deployment configuration. Do not substitute a different service image during a baseline test. |

## Results that are not implementation findings

An early Feature Engineering trial failed because its test fixture did not rename `datetime` to `timestamp`. The service correctly rejected that input. The final feature-engineering test and the full integrated workflow used the explicit mapping and completed successfully.

Earlier package drafts also had ordering and service-name mistakes. They were corrected before the recorded final run. They are not defects in the Portugal node.
