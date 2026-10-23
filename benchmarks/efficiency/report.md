# Efficiency benchmark

**Recorded observations; no comparison yet.** These results are not quality approval.

Each series contains three trials. Per-trial figures below are **medians**; explicitly labelled totals cover all three trials. These are independent screening observations, not proof of statistical significance or causality.

## Performance and consumption

| Measure | Recorded result |
| --- | --- |
| Measured benchmark time per trial | 19 min 20 s |
| Consumption per trial | 300.43 |
| Model requests per trial | 170 |
| Input tokens per trial | 12,054,222 |
| Output tokens per trial | 231,874 |
| Tool calls per trial | 266 |

Total consumption across all three trials: **861.60**.
Consumption is measured in credits, not currency. Measured benchmark time combines workflow-stage wall time and the independent judge. Stage clocks include some harness checks, not just agent subprocess execution; preparation, report generation and some independent evaluation are excluded. Pure agent latency and whole-wizard duration are not measured. Every sample and the complete numeric data are retained in `report.json`; detailed tables appear below.

| Timing boundary (median per trial) | Recorded result |
| --- | --- |
| Workflow-stage wall time (includes harness checks) | 19 min 6.7 s |
| Independent-judge time | 0 min 13.3 s |
Combined medians are reduced from per-trial stage-plus-judge sums, not added component medians.

## Document quality and acceptance

| Measure | Recorded result |
| --- | --- |
| Document quality (median /100) | 83/100 |
| Functional acceptance | 3 of 3 trials |
| Full workflow acceptance | 0 of 3 trials |
| Failed tool calls (total) | 24 |
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
| Build: developer | 2 of 3 |
| Build: lead | 2 of 3 |
| Build: researcher | 2 of 3 |
| Build: Review outcome | 2 of 3 |
| Build: State verification | 2 of 3 |
| Build: tester | 2 of 3 |
| Full workflow acceptance | 0 of 3 |
| Requirements: BRD reviewer deliverable acceptance | 0 of 3 |
| Requirements: PRD reviewer deliverable acceptance | 0 of 3 |
| Requirements: Review outcome | 0 of 3 |
| Requirements: State verification | 2 of 3 |
| Requirements: tester | 2 of 3 |
| Stage readiness: Build | 1 of 3 |
| Stage readiness: Requirements | 0 of 3 |
| Final workflow readiness | 1 of 3 |
| Final workflow readiness: developer | 2 of 3 |
| Final workflow readiness: lead | 2 of 3 |
| Final workflow readiness: researcher | 2 of 3 |
| Final workflow readiness: Review outcome | 2 of 3 |
| Final workflow readiness: State verification | 2 of 3 |
| Final workflow readiness: tester | 2 of 3 |

Reviewer dispatch and reviewer file-deliverable acceptance are different checks. A reviewer may have been dispatched even when its required deliverable check fails.

<details>
<summary>All measurements, samples and checks</summary>

Resource tables use exact values: median [minimum, maximum]; individual samples; series total. Time is in seconds unless explicitly labelled as an event interval in milliseconds; event intervals are diagnostic, not end-to-end timing.

## workflow resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 296.4974885 [257.111005, 296.611212]; 296.4974885, 296.611212, 257.111005; 850.2197055 |
| requests | n/a (unavailable) | 169 [150, 186]; 150, 186, 169; 505 |
| inputTokens | n/a (unavailable) | 12041694 [10499790, 13467069]; 10499790, 13467069, 12041694; 36008553 |
| outputTokens | n/a (unavailable) | 230962 [198312, 241259]; 198312, 241259, 230962; 670533 |
| toolCalls | n/a (unavailable) | 266 [249, 299]; 249, 299, 266; 814 |
| failedTools | n/a (unavailable) | 9 [5, 10]; 5, 9, 10; 24 |
| measuredProcessWallSeconds | n/a (unavailable) | 1146.668 [1119.934, 1259.094]; 1146.668, 1259.094, 1119.934; 3525.696 |
| cacheReadTokens | n/a (unavailable) | 11057738 [9261510, 12362478]; 9261510, 12362478, 11057738; 32681726 |
| cacheWriteTokens | n/a (unavailable) | 1088720 [969535, 1225496]; 1225496, 1088720, 969535; 3283751 |
| eventElapsedMs | n/a (unavailable) | 1142818 [1116506, 1255606]; 1142818, 1255606, 1116506; 3514930 |

## judge resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 3.89243 [3.55318, 3.93443]; 3.93443, 3.89243, 3.55318; 11.38004 |
| requests | n/a (unavailable) | 1 [1, 1]; 1, 1, 1; 3 |
| inputTokens | n/a (unavailable) | 13981 [12528, 14285]; 14285, 13981, 12528; 40794 |
| outputTokens | n/a (unavailable) | 888 [854, 912]; 854, 888, 912; 2654 |
| toolCalls | n/a (unavailable) | 0 [0, 0]; 0, 0, 0; 0 |
| failedTools | n/a (unavailable) | 0 [0, 0]; 0, 0, 0; 0 |
| measuredProcessWallSeconds | n/a (unavailable) | 13.304 [12.485, 14.068]; 13.304, 12.485, 14.068; 39.857 |
| cacheReadTokens | n/a (unavailable) | 2028 [2028, 2028]; 2028, 2028, 2028; 6084 |
| cacheWriteTokens | n/a (unavailable) | 11871 [10418, 12175]; 12175, 11871, 10418; 34464 |
| eventElapsedMs | n/a (unavailable) | 10335 [10008, 10714]; 10335, 10008, 10714; 31057 |

## total resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | n/a (unavailable) | 300.4319185 [260.664185, 300.503642]; 300.4319185, 300.503642, 260.664185; 861.5997455 |
| requests | n/a (unavailable) | 170 [151, 187]; 151, 187, 170; 508 |
| inputTokens | n/a (unavailable) | 12054222 [10514075, 13481050]; 10514075, 13481050, 12054222; 36049347 |
| outputTokens | n/a (unavailable) | 231874 [199166, 242147]; 199166, 242147, 231874; 673187 |
| toolCalls | n/a (unavailable) | 266 [249, 299]; 249, 299, 266; 814 |
| failedTools | n/a (unavailable) | 9 [5, 10]; 5, 9, 10; 24 |
| measuredProcessWallSeconds | n/a (unavailable) | 1159.972 [1134.002, 1271.579]; 1159.972, 1271.579, 1134.002; 3565.553 |
| cacheReadTokens | n/a (unavailable) | 11059766 [9263538, 12364506]; 9263538, 12364506, 11059766; 32687810 |
| cacheWriteTokens | n/a (unavailable) | 1100591 [979953, 1237671]; 1237671, 1100591, 979953; 3318215 |
| eventElapsedMs | n/a (unavailable) | 1153153 [1127220, 1265614]; 1153153, 1265614, 1127220; 3545987 |

## Quality and reliability

| Metric | Base | Head |
|---|---|---|
| quality/businessClarity | n/a | 18 [17, 18]; 18, 18, 17 |
| quality/scopeFidelity | n/a | 17 [17, 18]; 17, 18, 17 |
| quality/acceptanceCriteria | n/a | 16 [16, 17]; 16, 16, 17 |
| quality/traceability | n/a | 17 [16, 17]; 17, 17, 16 |
| quality/risksAndDecisions | n/a | 15 [14, 15]; 15, 14, 15 |
| quality/total | n/a | 83 [82, 83]; 83, 83, 82 |
| criticalHighFindings | n/a | 2 |
| build/consumption-rates.md | n/a | 3/3 |
| build/consumption.md | n/a | 3/3 |
| build/decisions.md | n/a | 3/3 |
| build/developer | n/a | 2/3 |
| build/dispatchEvidence | n/a | 3/3 |
| build/lead | n/a | 2/3 |
| build/researcher | n/a | 2/3 |
| build/reviewOutcome | n/a | 2/3 |
| build/routing.md | n/a | 3/3 |
| build/state.json | n/a | 3/3 |
| build/stateVerifier | n/a | 2/3 |
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
| init/scribeHistory | n/a | 3/3 |
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
| requirements/reviewOutcome | n/a | 0/3 |
| requirements/routing.md | n/a | 3/3 |
| requirements/scribeHistory | n/a | 3/3 |
| requirements/state.json | n/a | 3/3 |
| requirements/stateVerifier | n/a | 2/3 |
| requirements/team.md | n/a | 3/3 |
| requirements/tester | n/a | 2/3 |
| stage/build | n/a | 1/3 |
| stage/init | n/a | 3/3 |
| stage/requirements | n/a | 0/3 |
| workflow | n/a | 1/3 |
| workflow/consumption-rates.md | n/a | 3/3 |
| workflow/consumption.md | n/a | 3/3 |
| workflow/decisions.md | n/a | 3/3 |
| workflow/developer | n/a | 2/3 |
| workflow/dispatchEvidence | n/a | 3/3 |
| workflow/lead | n/a | 2/3 |
| workflow/researcher | n/a | 2/3 |
| workflow/reviewOutcome | n/a | 2/3 |
| workflow/routing.md | n/a | 3/3 |
| workflow/state.json | n/a | 3/3 |
| workflow/stateVerifier | n/a | 2/3 |
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
| headCommit | 59880d5c0417e99a7fe6ab5f12670f8bd9b7401b |
| mergeBase | n/a |
| policyHash | n/a |
| Recorded / candidate seriesId | run-20261021-102320-92ef357d |
| Recorded / candidate sha256 | d8f8932861e63e03473d9d71a54df086c15a62a3285c414d89d51050d7185f49 |
| Recorded / candidate sourceHash | c69a057c35921bd53843bf407f9e135c30f655b6d301c69b9d5fa939b05a3e98 |
| Recorded / candidate measuredRevision | 59880d5c0417e99a7fe6ab5f12670f8bd9b7401b |

### Recorded / candidate protocol

| Field | Value |
|---|---|
| cliVersion | 1.0.101-0 |
| continuations | 1000 |
| converterHash | 20773d56958398348e9986acb2a67b56c65ad098f8b201cffb1700890c969503 |
| disabledMcpServersHash | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| evaluationPolicy | baseline-observation-v1 |
| exerciseHash | 5926ff2d90efb06969d614bbe8e51d5d03076af8db5cca93297870b0af32cd80 |
| graderHash | 4742c58915327e9f8ee74c137161a29a886dca304d2ea15ff9e92cd60ab84139 |
| hostProfile | native-cli-references |
| installHash | ea18bb50c23b66c1bcc2366c452063897c7869969cf4a2ed0d2d2435e97936f5 |
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
