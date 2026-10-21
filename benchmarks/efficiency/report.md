# Efficiency benchmark

**Recorded observations; no comparison yet.** These results are not quality approval.

Each series contains three trials. Per-trial figures below are **medians**; explicitly labelled totals cover all three trials. These are independent screening observations, not proof of statistical significance or causality.

## Performance and consumption

| Measure | Recorded result |
| --- | --- |
| Measured benchmark time per trial | 11 min 18.4 s |
| Consumption per trial | 252.95 |
| Model requests per trial | 88 |
| Input tokens per trial | 5,570,399 |
| Output tokens per trial | 98,705 |
| Tool calls per trial | 96 |

Total consumption across all three trials: **739.64**.
Consumption is measured in credits, not currency. Measured benchmark time combines workflow-stage wall time and the independent judge. Stage clocks include some harness checks, not just agent subprocess execution; preparation, report generation and some independent evaluation are excluded. Pure agent latency and whole-wizard duration are not measured. Every sample and the complete numeric data are retained in `report.json`; detailed tables appear below.

| Timing boundary (median per trial) | Recorded result |
| --- | --- |
| Workflow-stage wall time (includes harness checks) | 11 min 3.4 s |
| Independent-judge time | 0 min 12.7 s |
Combined medians are reduced from per-trial stage-plus-judge sums, not added component medians.

## Document quality and acceptance

| Measure | Recorded result |
| --- | --- |
| Document quality (median /100) | 81/100 |
| Functional acceptance | 3 of 3 trials |
| Full workflow acceptance | 0 of 3 trials |
| Failed tool calls (total) | 19 |
| Critical/high findings (total) | 5 |

Functional acceptance requires every functional probe to pass. **Full workflow acceptance** also requires every stage and the final workflow checks to pass. A successful process exit or final build alone is not full acceptance.

Observed total consumption per accepted workflow: Recorded result: Unavailable (0 accepted workflows).
This descriptive ratio includes consumption from every recorded attempt, not just successful ones; it is not expected retry cost. Document quality scores assess BRD/PRD content, not delivered software quality. Expert calibration and statistical significance have not been established.

## Comparison findings

- No baseline comparison was requested.

## Checks needing attention

Only checks that did not pass in all three trials are shown here. The complete check list, including passing checks, is available in the details below.

| Check | Recorded result |
| --- | --- |
| Build: Review outcome | 1 of 3 |
| Build: tester | 2 of 3 |
| Full workflow acceptance | 0 of 3 |
| Initialization: Scribe history | 2 of 3 |
| Requirements: PRD reviewer deliverable acceptance | 1 of 3 |
| Requirements: Review outcome | 0 of 3 |
| Requirements: Scribe history | 2 of 3 |
| Requirements: tester | 2 of 3 |
| Stage readiness: Build | 1 of 3 |
| Stage readiness: Initialization | 2 of 3 |
| Stage readiness: Requirements | 0 of 3 |
| Final workflow readiness | 1 of 3 |
| Final workflow readiness: Review outcome | 1 of 3 |
| Final workflow readiness: tester | 2 of 3 |

Reviewer dispatch and reviewer file-deliverable acceptance are different checks. A reviewer may have been dispatched even when its required deliverable check fails.

<details>
<summary>All measurements, samples and checks</summary>

Resource tables use exact values: median [minimum, maximum]; individual samples; series total. Time is in seconds unless explicitly labelled as an event interval in milliseconds; event intervals are diagnostic, not end-to-end timing.

## workflow resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 249.3589165 [219.763994, 259.8167265]; 259.8167265, 219.763994, 249.3589165; 728.939637 |
| requests | n/a (unavailable) | 87 [78, 99]; 78, 87, 99; 264 |
| inputTokens | n/a (unavailable) | 5556186 [5521558, 6304163]; 5556186, 5521558, 6304163; 17381907 |
| outputTokens | n/a (unavailable) | 97838 [94915, 118419]; 97838, 94915, 118419; 311172 |
| toolCalls | n/a (unavailable) | 96 [89, 108]; 89, 96, 108; 293 |
| failedTools | n/a (unavailable) | 4 [4, 11]; 4, 4, 11; 19 |
| measuredProcessWallSeconds | n/a (unavailable) | 663.433 [634.651, 801.817]; 663.433, 634.651, 801.817; 2099.901 |
| cacheReadTokens | n/a (unavailable) | 4943940 [4927008, 5709200]; 4927008, 4943940, 5709200; 15580148 |
| cacheWriteTokens | n/a (unavailable) | 586508 [570193, 622514]; 622514, 570193, 586508; 1779215 |
| eventElapsedMs | n/a (unavailable) | 660286 [631128, 798538]; 660286, 631128, 798538; 2089952 |

## judge resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 3.58868 [3.18618, 3.92943]; 3.92943, 3.18618, 3.58868; 10.70429 |
| requests | n/a (unavailable) | 1 [1, 1]; 1, 1, 1; 3 |
| inputTokens | n/a (unavailable) | 12686 [11180, 14213]; 14213, 11180, 12686; 38079 |
| outputTokens | n/a (unavailable) | 882 [867, 908]; 867, 882, 908; 2657 |
| toolCalls | n/a (unavailable) | 0 [0, 0]; 0, 0, 0; 0 |
| failedTools | n/a (unavailable) | 0 [0, 0]; 0, 0, 0; 0 |
| measuredProcessWallSeconds | n/a (unavailable) | 12.723 [12.084, 14.938]; 14.938, 12.084, 12.723; 39.745 |
| cacheReadTokens | n/a (unavailable) | 2028 [2028, 2028]; 2028, 2028, 2028; 6084 |
| cacheWriteTokens | n/a (unavailable) | 10576 [9070, 12103]; 12103, 9070, 10576; 31749 |
| eventElapsedMs | n/a (unavailable) | 10209 [9651, 10621]; 10621, 9651, 10209; 30481 |

## total resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 252.9475965 [222.950174, 263.7461565]; 263.7461565, 222.950174, 252.9475965; 739.643927 |
| requests | n/a (unavailable) | 88 [79, 100]; 79, 88, 100; 267 |
| inputTokens | n/a (unavailable) | 5570399 [5532738, 6316849]; 5570399, 5532738, 6316849; 17419986 |
| outputTokens | n/a (unavailable) | 98705 [95797, 119327]; 98705, 95797, 119327; 313829 |
| toolCalls | n/a (unavailable) | 96 [89, 108]; 89, 96, 108; 293 |
| failedTools | n/a (unavailable) | 4 [4, 11]; 4, 4, 11; 19 |
| measuredProcessWallSeconds | n/a (unavailable) | 678.371 [646.735, 814.54]; 678.371, 646.735, 814.54; 2139.646 |
| cacheReadTokens | n/a (unavailable) | 4945968 [4929036, 5711228]; 4929036, 4945968, 5711228; 15586232 |
| cacheWriteTokens | n/a (unavailable) | 597084 [579263, 634617]; 634617, 579263, 597084; 1810964 |
| eventElapsedMs | n/a (unavailable) | 670907 [640779, 808747]; 670907, 640779, 808747; 2120433 |

## Quality and reliability

| Metric | Base | Head |
|---|---|---|
| quality/businessClarity | n/a | 17 [16, 18]; 18, 16, 17 |
| quality/scopeFidelity | n/a | 17 [17, 18]; 17, 18, 17 |
| quality/acceptanceCriteria | n/a | 17 [16, 17]; 16, 17, 17 |
| quality/traceability | n/a | 15 [15, 16]; 16, 15, 15 |
| quality/risksAndDecisions | n/a | 15 [14, 16]; 14, 16, 15 |
| quality/total | n/a | 81 [81, 82]; 81, 82, 81 |
| criticalHighFindings | n/a | 5 |
| build/consumption-rates.md | n/a | 3/3 |
| build/consumption.md | n/a | 3/3 |
| build/decisions.md | n/a | 3/3 |
| build/developer | n/a | 3/3 |
| build/dispatchEvidence | n/a | 3/3 |
| build/lead | n/a | 3/3 |
| build/researcher | n/a | 3/3 |
| build/reviewOutcome | n/a | 1/3 |
| build/routing.md | n/a | 3/3 |
| build/state.json | n/a | 3/3 |
| build/stateVerifier | n/a | 3/3 |
| build/team.md | n/a | 3/3 |
| build/tester | n/a | 2/3 |
| completed | n/a | 0/3 |
| functional | n/a | 3/3 |
| functional/add-unicode | n/a | 3/3 |
| functional/blank-title | n/a | 3/3 |
| functional/corrupt-store-preserved | n/a | 3/3 |
| functional/done-idempotent | n/a | 3/3 |
| functional/empty-list | n/a | 3/3 |
| functional/id-boundary-preserves-store | n/a | 3/3 |
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
| requirements/BRD Quality Reviewer | n/a | 3/3 |
| requirements/brd.md | n/a | 3/3 |
| requirements/consumption-rates.md | n/a | 3/3 |
| requirements/consumption.md | n/a | 3/3 |
| requirements/decisions.md | n/a | 3/3 |
| requirements/dispatchEvidence | n/a | 3/3 |
| requirements/PRD Builder | n/a | 3/3 |
| requirements/PRD Quality Reviewer | n/a | 1/3 |
| requirements/prd.md | n/a | 3/3 |
| requirements/reviewOutcome | n/a | 0/3 |
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
| workflow/reviewOutcome | n/a | 1/3 |
| workflow/routing.md | n/a | 3/3 |
| workflow/state.json | n/a | 3/3 |
| workflow/stateVerifier | n/a | 3/3 |
| workflow/team.md | n/a | 3/3 |
| workflow/tester | n/a | 2/3 |
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
| headCommit | 4d4de7c73ef886cf6ab6003f874d63cd686e8139 |
| mergeBase | n/a |
| policyHash | n/a |
| Recorded / candidate seriesId | run-20261021-123337-96e88690-v2 |
| Recorded / candidate sha256 | f6fae24bea9cabc419f5ac371e39c1cf02b60d284b9e28408855fcbfcc096b08 |
| Recorded / candidate sourceHash | 37e0f5f4fb6213643e53280fe86dacab8988450b711715a47467d40f4295d961 |
| Recorded / candidate measuredRevision | 4d4de7c73ef886cf6ab6003f874d63cd686e8139 |

### Recorded / candidate protocol

| Field | Value |
|---|---|
| cliVersion | 1.0.102-1 |
| continuations | 1000 |
| converterHash | 20773d56958398348e9986acb2a67b56c65ad098f8b201cffb1700890c969503 |
| disabledMcpServersHash | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| evaluationPolicy | baseline-observation-v1 |
| exerciseHash | 5926ff2d90efb06969d614bbe8e51d5d03076af8db5cca93297870b0af32cd80 |
| graderHash | 4742c58915327e9f8ee74c137161a29a886dca304d2ea15ff9e92cd60ab84139 |
| hostProfile | native-cli-references |
| installHash | c5f4139cd070c6f624ece9f8ad7154b07d7904bb5fbcb001868e7cb7c5ac045b |
| maxCredits | 1000 |
| model | claude-sonnet-5.5 |
| parserHash | 03a10dec2d38fd327e11ee87e243579f285c804d96c2ce11676b91940501dd7f |
| powershell | 7.6.7 |
| preparationHash | e4c7372091a8e5a9dbe84690d4ef48841cd9f5ecaac8b053577e4eee1bc35eb2 |
| recoveryPolicy | baseline-observation-v1 |
| roleModelPolicyHash | 007d8f0e7464108bca76256cceb8677cf373c62eed1dcba4e2df98b598e227eb |
| rubric | requirements-quality-v1 |
| scenarioHash | 4946fca0eeab4ca66c030a378cda3dcbbc9b720dbaeb729546480e92e4c7787d |
| schema | squad-efficiency-v1 |
| verifierHash | 4cd521dced1ebd72a14148800cc8841488dfeec1f21b9b66a655363a10e46834 |

Machine reasons: no-comparison-claimed

</details>
