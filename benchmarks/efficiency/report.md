# Efficiency benchmark

**Recorded observations; no comparison yet.** These results are not quality approval.

Each series contains three trials. Per-trial figures below are **medians**; explicitly labelled totals cover all three trials. These are independent screening observations, not proof of statistical significance or causality.

## Performance and consumption

| Measure | Recorded result |
| --- | --- |
| Measured benchmark time per trial | 17 min 36.2 s |
| Consumption per trial | 229.96 |
| Model requests per trial | 151 |
| Input tokens per trial | 10,349,971 |
| Output tokens per trial | 217,595 |
| Tool calls per trial | 278 |

Total consumption across all three trials: **714.23**.
Consumption is measured in credits, not currency. Measured benchmark time combines workflow-stage wall time and the independent judge. Stage clocks include some harness checks, not just agent subprocess execution; preparation, report generation and some independent evaluation are excluded. Pure agent latency and whole-wizard duration are not measured. Every sample and the complete numeric data are retained in `report.json`; detailed tables appear below.

| Timing boundary (median per trial) | Recorded result |
| --- | --- |
| Workflow-stage wall time (includes harness checks) | 17 min 21.7 s |
| Independent-judge time | 0 min 12.8 s |
Combined medians are reduced from per-trial stage-plus-judge sums, not added component medians.

## Document quality and acceptance

| Measure | Recorded result |
| --- | --- |
| Document quality (median /100) | 83/100 |
| Functional acceptance | 2 of 3 trials |
| Full workflow acceptance | 0 of 3 trials |
| Failed tool calls (total) | 26 |
| Critical/high findings (total) | 2 |

Functional acceptance requires every functional probe to pass. **Full workflow acceptance** also requires every stage and the final workflow checks to pass. A successful process exit or final build alone is not full acceptance.

Observed total consumption per accepted workflow: Recorded result: Unavailable (0 accepted workflows).
This descriptive ratio includes consumption from every recorded attempt, not just successful ones; it is not expected retry cost. Document quality scores assess BRD/PRD content, not delivered software quality. Expert calibration and statistical significance have not been established.

## Comparison findings

- No baseline comparison was requested.

## Checks needing attention

Only checks that did not pass in all three trials are shown here. The complete check list, including passing checks, is available in the details below.

| Check | Recorded result |
| --- | --- |
| Build: Review outcome | 2 of 3 |
| Build: State verification | 2 of 3 |
| Full workflow acceptance | 0 of 3 |
| All functional checks | 2 of 3 |
| All functional checks: ID boundary preserves stored data | 2 of 3 |
| Initialization: Scribe history | 2 of 3 |
| Requirements: BRD reviewer deliverable acceptance | 0 of 3 |
| Requirements: PRD reviewer deliverable acceptance | 0 of 3 |
| Requirements: Review outcome | 1 of 3 |
| Requirements: Scribe history | 2 of 3 |
| Requirements: tester | 2 of 3 |
| Stage readiness: Build | 1 of 3 |
| Stage readiness: Initialization | 2 of 3 |
| Stage readiness: Requirements | 0 of 3 |
| Final workflow readiness | 1 of 3 |
| Final workflow readiness: Review outcome | 2 of 3 |
| Final workflow readiness: State verification | 2 of 3 |

Reviewer dispatch and reviewer file-deliverable acceptance are different checks. A reviewer may have been dispatched even when its required deliverable check fails.

<details>
<summary>All measurements, samples and checks</summary>

Resource tables use exact values: median [minimum, maximum]; individual samples; series total. Time is in seconds unless explicitly labelled as an event interval in milliseconds; event intervals are diagnostic, not end-to-end timing.

## workflow resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 226.4625795 [223.9845755, 253.3484105]; 223.9845755, 226.4625795, 253.3484105; 703.7955655 |
| requests | n/a (unavailable) | 150 [144, 195]; 144, 150, 195; 489 |
| inputTokens | n/a (unavailable) | 10337366 [10270930, 14163099]; 10337366, 10270930, 14163099; 34771395 |
| outputTokens | n/a (unavailable) | 216737 [196929, 232301]; 196929, 216737, 232301; 645967 |
| toolCalls | n/a (unavailable) | 278 [243, 342]; 243, 278, 342; 863 |
| failedTools | n/a (unavailable) | 8 [7, 11]; 8, 7, 11; 26 |
| measuredProcessWallSeconds | n/a (unavailable) | 1041.709 [1041.238, 1180.951]; 1041.238, 1041.709, 1180.951; 3263.898 |
| cacheReadTokens | n/a (unavailable) | 9363453 [9237323, 12955928]; 9363453, 9237323, 12955928; 31556704 |
| cacheWriteTokens | n/a (unavailable) | 1020823 [961629, 1190537]; 961629, 1020823, 1190537; 3172989 |
| eventElapsedMs | n/a (unavailable) | 1037985 [1037718, 1174415]; 1037718, 1037985, 1174415; 3250118 |

## judge resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 3.49643 [3.43418, 3.50343]; 3.50343, 3.49643, 3.43418; 10.43404 |
| requests | n/a (unavailable) | 1 [1, 1]; 1, 1, 1; 3 |
| inputTokens | n/a (unavailable) | 12517 [12228, 12605]; 12605, 12517, 12228; 37350 |
| outputTokens | n/a (unavailable) | 858 [843, 868]; 843, 858, 868; 2569 |
| toolCalls | n/a (unavailable) | 0 [0, 0]; 0, 0, 0; 0 |
| failedTools | n/a (unavailable) | 0 [0, 0]; 0, 0, 0; 0 |
| measuredProcessWallSeconds | n/a (unavailable) | 12.789 [12.587, 14.479]; 12.789, 14.479, 12.587; 39.855 |
| cacheReadTokens | n/a (unavailable) | 2028 [2028, 2028]; 2028, 2028, 2028; 6084 |
| cacheWriteTokens | n/a (unavailable) | 10407 [10118, 10495]; 10495, 10407, 10118; 31020 |
| eventElapsedMs | n/a (unavailable) | 9912 [9861, 10901]; 9861, 10901, 9912; 30674 |

## total resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 229.9590095 [227.4880055, 256.7825905]; 227.4880055, 229.9590095, 256.7825905; 714.2296055 |
| requests | n/a (unavailable) | 151 [145, 196]; 145, 151, 196; 492 |
| inputTokens | n/a (unavailable) | 10349971 [10283447, 14175327]; 10349971, 10283447, 14175327; 34808745 |
| outputTokens | n/a (unavailable) | 217595 [197772, 233169]; 197772, 217595, 233169; 648536 |
| toolCalls | n/a (unavailable) | 278 [243, 342]; 243, 278, 342; 863 |
| failedTools | n/a (unavailable) | 8 [7, 11]; 8, 7, 11; 26 |
| measuredProcessWallSeconds | n/a (unavailable) | 1056.188 [1054.027, 1193.538]; 1054.027, 1056.188, 1193.538; 3303.753 |
| cacheReadTokens | n/a (unavailable) | 9365481 [9239351, 12957956]; 9365481, 9239351, 12957956; 31562788 |
| cacheWriteTokens | n/a (unavailable) | 1031230 [972124, 1200655]; 972124, 1031230, 1200655; 3204009 |
| eventElapsedMs | n/a (unavailable) | 1048886 [1047579, 1184327]; 1047579, 1048886, 1184327; 3280792 |

## Quality and reliability

| Metric | Base | Head |
|---|---|---|
| quality/businessClarity | n/a | 17 [17, 18]; 17, 17, 18 |
| quality/scopeFidelity | n/a | 17 [17, 18]; 18, 17, 17 |
| quality/acceptanceCriteria | n/a | 16 [16, 17]; 17, 16, 16 |
| quality/traceability | n/a | 17 [15, 17]; 17, 15, 17 |
| quality/risksAndDecisions | n/a | 15 [14, 16]; 14, 15, 16 |
| quality/total | n/a | 83 [80, 84]; 83, 80, 84 |
| criticalHighFindings | n/a | 2 |
| build/consumption-rates.md | n/a | 3/3 |
| build/consumption.md | n/a | 3/3 |
| build/decisions.md | n/a | 3/3 |
| build/developer | n/a | 3/3 |
| build/dispatchEvidence | n/a | 3/3 |
| build/lead | n/a | 3/3 |
| build/researcher | n/a | 3/3 |
| build/reviewOutcome | n/a | 2/3 |
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
| init/scribeHistory | n/a | 2/3 |
| init/state.json | n/a | 3/3 |
| init/stateVerifier | n/a | 3/3 |
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
| requirements/reviewOutcome | n/a | 1/3 |
| requirements/routing.md | n/a | 3/3 |
| requirements/scribeHistory | n/a | 2/3 |
| requirements/state.json | n/a | 3/3 |
| requirements/stateVerifier | n/a | 3/3 |
| requirements/team.md | n/a | 3/3 |
| requirements/tester | n/a | 2/3 |
| stage/build | n/a | 1/3 |
| stage/init | n/a | 2/3 |
| stage/requirements | n/a | 0/3 |
| workflow | n/a | 1/3 |
| workflow/consumption-rates.md | n/a | 3/3 |
| workflow/consumption.md | n/a | 3/3 |
| workflow/decisions.md | n/a | 3/3 |
| workflow/developer | n/a | 3/3 |
| workflow/dispatchEvidence | n/a | 3/3 |
| workflow/lead | n/a | 3/3 |
| workflow/researcher | n/a | 3/3 |
| workflow/reviewOutcome | n/a | 2/3 |
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
| headCommit | 450dced9e2ffa9bc43fc99c4e115d21124bfb86b |
| mergeBase | n/a |
| policyHash | n/a |
| Recorded / candidate seriesId | run-20261020-132749-1631c251 |
| Recorded / candidate sha256 | d48343d8b1f0a4517cfb3f60dfef44ca2dcceecb5fa918c5b6fb992d93daca3a |
| Recorded / candidate sourceHash | c69a057c35921bd53843bf407f9e135c30f655b6d301c69b9d5fa939b05a3e98 |
| Recorded / candidate measuredRevision | 450dced9e2ffa9bc43fc99c4e115d21124bfb86b |

### Recorded / candidate protocol

| Field | Value |
|---|---|
| cliVersion | 1.0.101-0 |
| continuations | 1000 |
| disabledMcpServersHash | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| evaluationPolicy | baseline-observation-v1 |
| exerciseHash | 3b16c298fa8cad268555b087aadd409031e2adf9cf174b0e9f89ea38e9aefc20 |
| graderHash | 4742c58915327e9f8ee74c137161a29a886dca304d2ea15ff9e92cd60ab84139 |
| hostProfile | native-cli-references |
| installHash | 92fc784ec2592142156d9bc1704f00d27231410e7a62742aed14fb8b3805fa67 |
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
