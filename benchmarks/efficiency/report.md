# Efficiency benchmark

**Recorded observations; no comparison yet.** These results are not quality approval.

Each series contains three trials. Per-trial figures below are **medians**; explicitly labelled totals cover all three trials. These are independent screening observations, not proof of statistical significance or causality.

## Performance and consumption

| Measure | Recorded result |
| --- | --- |
| Measured benchmark time per trial | 17 min 45.6 s |
| Consumption per trial | 250.47 |
| Model requests per trial | 170 |
| Input tokens per trial | 12,177,554 |
| Output tokens per trial | 219,267 |
| Tool calls per trial | 280 |

Total consumption across all three trials: **760.64**.
Consumption is measured in credits, not currency. Measured benchmark time combines workflow-stage wall time and the independent judge. Stage clocks include some harness checks, not just agent subprocess execution; preparation, report generation and some independent evaluation are excluded. Pure agent latency and whole-wizard duration are not measured. Every sample and the complete numeric data are retained in `report.json`; detailed tables appear below.

| Timing boundary (median per trial) | Recorded result |
| --- | --- |
| Workflow-stage wall time (includes harness checks) | 17 min 32.3 s |
| Independent-judge time | 0 min 13.2 s |
Combined medians are reduced from per-trial stage-plus-judge sums, not added component medians.

## Document quality and acceptance

| Measure | Recorded result |
| --- | --- |
| Document quality (median /100) | 86/100 |
| Functional acceptance | 2 of 3 trials |
| Full workflow acceptance | 0 of 3 trials |
| Failed tool calls (total) | 10 |
| Critical/high findings (total) | 1 |

Functional acceptance requires every functional probe to pass. **Full workflow acceptance** also requires every stage and the final workflow checks to pass. A successful process exit or final build alone is not full acceptance.

Observed total consumption per accepted workflow: Recorded result: Unavailable (0 accepted workflows).
This descriptive ratio includes consumption from every recorded attempt, not just successful ones; it is not expected retry cost. Document quality scores assess BRD/PRD content, not delivered software quality. Expert calibration and statistical significance have not been established.

## Comparison findings

- No baseline comparison was requested.

## Checks needing attention

Only checks that did not pass in all three trials are shown here. The complete check list, including passing checks, is available in the details below.

| Check | Recorded result |
| --- | --- |
| Build: State verification | 2 of 3 |
| Full workflow acceptance | 0 of 3 |
| All functional checks | 2 of 3 |
| All functional checks: ID boundary preserves stored data | 2 of 3 |
| Initialization: State verification | 2 of 3 |
| Requirements: BRD reviewer deliverable acceptance | 0 of 3 |
| Requirements: PRD reviewer deliverable acceptance | 0 of 3 |
| Requirements: Review outcome | 2 of 3 |
| Requirements: State verification | 2 of 3 |
| Stage readiness: Build | 2 of 3 |
| Stage readiness: Initialization | 2 of 3 |
| Stage readiness: Requirements | 0 of 3 |
| Final workflow readiness | 2 of 3 |
| Final workflow readiness: State verification | 2 of 3 |

Reviewer dispatch and reviewer file-deliverable acceptance are different checks. A reviewer may have been dispatched even when its required deliverable check fails.

<details>
<summary>All measurements, samples and checks</summary>

Resource tables use exact values: median [minimum, maximum]; individual samples; series total. Time is in seconds unless explicitly labelled as an event interval in milliseconds; event intervals are diagnostic, not end-to-end timing.

## workflow resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 246.3776325 [238.062016, 264.5186265]; 246.3776325, 238.062016, 264.5186265; 748.958275 |
| requests | n/a (unavailable) | 169 [157, 174]; 169, 157, 174; 500 |
| inputTokens | n/a (unavailable) | 12162359 [10832024, 12538300]; 12162359, 10832024, 12538300; 35532683 |
| outputTokens | n/a (unavailable) | 218485 [196121, 226181]; 218485, 196121, 226181; 640787 |
| toolCalls | n/a (unavailable) | 280 [250, 290]; 280, 250, 290; 820 |
| failedTools | n/a (unavailable) | 4 [2, 4]; 4, 2, 4; 10 |
| measuredProcessWallSeconds | n/a (unavailable) | 1052.312 [1022.545, 1104.376]; 1104.376, 1022.545, 1052.312; 3179.233 |
| cacheReadTokens | n/a (unavailable) | 11070529 [9917117, 11391609]; 11070529, 9917117, 11391609; 32379255 |
| cacheWriteTokens | n/a (unavailable) | 1077421 [901508, 1131865]; 1077421, 901508, 1131865; 3110794 |
| eventElapsedMs | n/a (unavailable) | 1048733 [1019216, 1100228]; 1100228, 1019216, 1048733; 3168177 |

## judge resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 3.88293 [3.70718, 4.08993]; 4.08993, 3.88293, 3.70718; 11.68004 |
| requests | n/a (unavailable) | 1 [1, 1]; 1, 1, 1; 3 |
| inputTokens | n/a (unavailable) | 13931 [13404, 15195]; 15195, 13931, 13404; 42530 |
| outputTokens | n/a (unavailable) | 847 [782, 891]; 782, 891, 847; 2520 |
| toolCalls | n/a (unavailable) | 0 [0, 0]; 0, 0, 0; 0 |
| failedTools | n/a (unavailable) | 0 [0, 0]; 0, 0, 0; 0 |
| measuredProcessWallSeconds | n/a (unavailable) | 13.195 [12.575, 13.258]; 12.575, 13.195, 13.258; 39.028 |
| cacheReadTokens | n/a (unavailable) | 2028 [2028, 2028]; 2028, 2028, 2028; 6084 |
| cacheWriteTokens | n/a (unavailable) | 11821 [11294, 13085]; 13085, 11821, 11294; 36200 |
| eventElapsedMs | n/a (unavailable) | 10238 [9343, 10343]; 9343, 10238, 10343; 29924 |

## total resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 250.4675625 [241.944946, 268.2258065]; 250.4675625, 241.944946, 268.2258065; 760.638315 |
| requests | n/a (unavailable) | 170 [158, 175]; 170, 158, 175; 503 |
| inputTokens | n/a (unavailable) | 12177554 [10845955, 12551704]; 12177554, 10845955, 12551704; 35575213 |
| outputTokens | n/a (unavailable) | 219267 [197012, 227028]; 219267, 197012, 227028; 643307 |
| toolCalls | n/a (unavailable) | 280 [250, 290]; 280, 250, 290; 820 |
| failedTools | n/a (unavailable) | 4 [2, 4]; 4, 2, 4; 10 |
| measuredProcessWallSeconds | n/a (unavailable) | 1065.57 [1035.74, 1116.951]; 1116.951, 1035.74, 1065.57; 3218.261 |
| cacheReadTokens | n/a (unavailable) | 11072557 [9919145, 11393637]; 11072557, 9919145, 11393637; 32385339 |
| cacheWriteTokens | n/a (unavailable) | 1090506 [913329, 1143159]; 1090506, 913329, 1143159; 3146994 |
| eventElapsedMs | n/a (unavailable) | 1059076 [1029454, 1109571]; 1109571, 1029454, 1059076; 3198101 |

## Quality and reliability

| Metric | Base | Head |
|---|---|---|
| quality/businessClarity | n/a | 18 [17, 18]; 17, 18, 18 |
| quality/scopeFidelity | n/a | 17 [17, 18]; 17, 18, 17 |
| quality/acceptanceCriteria | n/a | 17 [15, 18]; 15, 17, 18 |
| quality/traceability | n/a | 17 [15, 18]; 15, 18, 17 |
| quality/risksAndDecisions | n/a | 16 [14, 17]; 14, 17, 16 |
| quality/total | n/a | 86 [78, 88]; 78, 88, 86 |
| criticalHighFindings | n/a | 1 |
| build/consumption-rates.md | n/a | 3/3 |
| build/consumption.md | n/a | 3/3 |
| build/decisions.md | n/a | 3/3 |
| build/developer | n/a | 3/3 |
| build/dispatchEvidence | n/a | 3/3 |
| build/lead | n/a | 3/3 |
| build/researcher | n/a | 3/3 |
| build/reviewOutcome | n/a | 3/3 |
| build/routing.md | n/a | 3/3 |
| build/state.json | n/a | 3/3 |
| build/stateVerifier | n/a | 2/3 |
| build/team.md | n/a | 3/3 |
| build/tester | n/a | 3/3 |
| completed | n/a | 0/3 |
| functional | n/a | 2/3 |
| functional/add-unicode | n/a | 3/3 |
| functional/blank-title | n/a | 3/3 |
| functional/corrupt-store-preserved | n/a | 3/3 |
| functional/done-idempotent | n/a | 3/3 |
| functional/empty-list | n/a | 3/3 |
| functional/id-boundary-preserves-store | n/a | 2/3 |
| functional/invalid-action | n/a | 3/3 |
| functional/invalid-filter | n/a | 3/3 |
| functional/missing-title | n/a | 3/3 |
| functional/persistent-ordered-list | n/a | 3/3 |
| functional/status-filter | n/a | 3/3 |
| functional/unique-increasing-id | n/a | 3/3 |
| functional/unknown-id | n/a | 3/3 |
| init/consumption-rates.md | n/a | 3/3 |
| init/consumption.md | n/a | 3/3 |
| init/decisions.md | n/a | 3/3 |
| init/dispatchEvidence | n/a | 3/3 |
| init/routing.md | n/a | 3/3 |
| init/scribeHistory | n/a | 3/3 |
| init/state.json | n/a | 3/3 |
| init/stateVerifier | n/a | 2/3 |
| init/team.md | n/a | 3/3 |
| requirements/BRD Builder | n/a | 3/3 |
| requirements/BRD Quality Reviewer | n/a | 0/3 |
| requirements/brd.md | n/a | 3/3 |
| requirements/consumption-rates.md | n/a | 3/3 |
| requirements/consumption.md | n/a | 3/3 |
| requirements/decisions.md | n/a | 3/3 |
| requirements/dispatchEvidence | n/a | 3/3 |
| requirements/PRD Builder | n/a | 3/3 |
| requirements/PRD Quality Reviewer | n/a | 0/3 |
| requirements/prd.md | n/a | 3/3 |
| requirements/reviewOutcome | n/a | 2/3 |
| requirements/routing.md | n/a | 3/3 |
| requirements/scribeHistory | n/a | 3/3 |
| requirements/state.json | n/a | 3/3 |
| requirements/stateVerifier | n/a | 2/3 |
| requirements/team.md | n/a | 3/3 |
| requirements/tester | n/a | 3/3 |
| stage/build | n/a | 2/3 |
| stage/init | n/a | 2/3 |
| stage/requirements | n/a | 0/3 |
| workflow | n/a | 2/3 |
| workflow/consumption-rates.md | n/a | 3/3 |
| workflow/consumption.md | n/a | 3/3 |
| workflow/decisions.md | n/a | 3/3 |
| workflow/developer | n/a | 3/3 |
| workflow/dispatchEvidence | n/a | 3/3 |
| workflow/lead | n/a | 3/3 |
| workflow/researcher | n/a | 3/3 |
| workflow/reviewOutcome | n/a | 3/3 |
| workflow/routing.md | n/a | 3/3 |
| workflow/state.json | n/a | 3/3 |
| workflow/stateVerifier | n/a | 2/3 |
| workflow/team.md | n/a | 3/3 |
| workflow/tester | n/a | 3/3 |
| observed brd reviewer dispatch (not file-deliverable acceptance) | n/a | 3/3 |
| observed prd reviewer dispatch (not file-deliverable acceptance) | n/a | 3/3 |

</details>

<details>
<summary>Provenance, compatibility and machine status</summary>

Machine status: **recorded-observation**; exit code **0**.
Integrity hashes and a reviewed workflow/controller do not authenticate model execution.

| Reference | Value |
|---|---|
| baseCommit | n/a |
| headCommit | e42002bfd51f79bb2e17d974d13b1fb66bc4099b |
| mergeBase | n/a |
| policyHash | n/a |
| Recorded / candidate seriesId | run-20261019-222802-3624af24 |
| Recorded / candidate sha256 | 7cad1c77998fe3cf22b723742485eade434b587eafe3153fde963e48a1bbc4ed |
| Recorded / candidate sourceHash | c69a057c35921bd53843bf407f9e135c30f655b6d301c69b9d5fa939b05a3e98 |
| Recorded / candidate measuredRevision | e42002bfd51f79bb2e17d974d13b1fb66bc4099b |

### Recorded / candidate protocol

| Field | Value |
|---|---|
| cliVersion | 1.0.101-0 |
| continuations | 1000 |
| disabledMcpServersHash | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| evaluationPolicy | baseline-observation-v1 |
| exerciseHash | 3b16c298fa8cad268555b087aadd409031e2adf9cf174b0e9f89ea38e9aefc20 |
| graderHash | bd92e8ab81dcc667bc5eacdf1b3e4b6a83a404f6be9e418cb529fdba5dafa8f7 |
| hostProfile | native-cli-references |
| installHash | ad2de4db2641d40c9baa51ae0d5e9c6f9fcb63ee5bf84b4aa644ee683a265e63 |
| maxCredits | 1000 |
| model | claude-sonnet-5.5 |
| parserHash | fa3aa1d09976a5a8c68862b439d3d5bf633b2d0024ec5594525bdc05cab4314c |
| powershell | 7.6.7 |
| preparationHash | d83bd90ffab57be4b79c8fa904c6a88588210423d11d9854fa01616ac9f5848c |
| recoveryPolicy | baseline-observation-v1 |
| roleModelPolicyHash | 2e4a47e7cbed5326653750e88eba035d9b2a7b8c9f09b47a15a9a3818bb3f76c |
| rubric | requirements-quality-v1 |
| scenarioHash | 4946fca0eeab4ca66c030a378cda3dcbbc9b720dbaeb729546480e92e4c7787d |
| schema | squad-efficiency-v1 |
| verifierHash | 4cd521dced1ebd72a14148800cc8841488dfeec1f21b9b66a655363a10e46834 |

Machine reasons: no-comparison-claimed

</details>
