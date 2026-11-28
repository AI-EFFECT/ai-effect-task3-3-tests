# UX evaluation protocol (UX-01, UX-02)

Task 3.3 asks for an assessment of the user interface and experience. The September closure had one expert review of the Dutch HAI interface. This protocol replaces it with a standard heuristic evaluation: several evaluators, working independently, using Nielsen's ten usability heuristics and a 0 to 4 severity scale.

## Interfaces in scope

| ID | Interface | Users it serves | How to reach it |
|---|---|---|---|
| `Dutch-HAI` | Human–AI Interaction session interface | Control-room operators | Signed session link from the Dutch suite (script 34 or 51 pattern) |
| `Danish-WebUI` | Danish node web UI | Engineers configuring a topology run | `http://127.0.0.1:18104` with the Danish stack running |
| `Service-Onboarding` | Onboarding a service with the templates, export generator and workflow submission | AI vendors and node developers | The platform onboarding guide and templates at the frozen commit |

The German and Portuguese nodes have no end-user interface. Their users are developers, which `Service-Onboarding` covers.

## Evaluators

- **3 to 5 evaluators per interface.** Fewer than three is recorded but does not meet the protocol.
- People with usability or energy-domain experience who did not build the interface. Use pseudonyms only (`E1`, `E2`, …); keep the key linking pseudonyms to names outside the evidence.
- Check with the Maynooth research ethics office whether colleagues acting as expert evaluators need approval. No personal data or user performance is recorded.

## Procedure per evaluator

1. The facilitator runs `40-New-UX-Evaluation-Forms.ps1 -Evaluator E<n> -Interface <ID>` and gives the evaluator a one-paragraph task brief:
    - **Dutch-HAI:** run one session to completion.
    - **Danish-WebUI:** request topologies for a named supply and load.
    - **Service-Onboarding:** onboard a provided sample service and run it.
2. The evaluator works alone for **60 to 90 minutes**, going through the interface at least twice: once to learn it, once to inspect it against each heuristic.
3. For each problem, the evaluator adds a row to `problems.csv`: heuristic (`H1`–`H10`), location, description and severity. They mark every heuristic as examined in `coverage.csv`.
4. Evaluators do not discuss findings until everyone has finished.

### Severity scale

| Score | Meaning |
|---|---|
| 0 | Not a usability problem |
| 1 | Cosmetic; fix if time allows |
| 2 | Minor |
| 3 | Major; important to fix |
| 4 | Catastrophic; must fix before release |

## Consolidation and summary

1. **Facilitator merges duplicates.** After all evaluators finish, the facilitator adds a `MergedId` column to each `problems.csv`, giving the same ID to the same problem found by different evaluators. The original rows stay unchanged.
2. **Run the summary.** `41-Summarise-UX-Evaluation.ps1` validates the forms and reports, per interface:
    - the unique problems;
    - the problems of severity 3 or 4;
    - how many evaluators found each problem;
    - the mean severity per heuristic.

## Evidence boundary

This is an expert inspection. It does not measure task success, satisfaction or accessibility with real users, and it is not a representative user study. Report its results as such.
