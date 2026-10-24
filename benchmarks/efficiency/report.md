# Efficiency benchmark

**Regression detected.** The candidate fails one or more comparison checks; resource savings do not override quality or reliability failures.

**Approximate historical comparison: the stored parent was measured in an older environment. All original metrics and protocol values are retained; this is not source-only causality or equal-environment evidence.**

Comparison scope: historical-reference
* installHash: old `ea18bb50c23b66c1bcc2366c452063897c7869969cf4a2ed0d2d2435e97936f5`; new `529a5170092a87c624a4f63c659781d011c29e64b714ea1498665cc5af564556`.

Each series contains three trials. Per-trial figures below are **medians**; explicitly labelled totals cover all three trials. These are independent screening observations, not proof of statistical significance or causality.

## Performance and consumption

| Measure | Baseline | Candidate | Change |
| --- | --- | --- | --- |
| Measured benchmark time per trial | 19 min 20 s | 13 min 26.8 s | 30.45% faster |
| Consumption per trial | 300.43 | 255.21 | 15.05% lower |
| Model requests per trial | 170 | 89 | 47.65% fewer |
| Input tokens per trial | 12,054,222 | 6,823,670 | 43.39% fewer |
| Output tokens per trial | 231,874 | 107,927 | 53.45% fewer |
| Tool calls per trial | 266 | 111 | 58.27% fewer |

Total consumption across all three trials: Baseline: **861.60**; Candidate: **801.43**.
Consumption is measured in credits, not currency. Measured benchmark time combines workflow-stage wall time and the independent judge. Stage clocks include some harness checks, not just agent subprocess execution; preparation, report generation and some independent evaluation are excluded. Pure agent latency and whole-wizard duration are not measured. Every sample and the complete numeric data are retained in `report.json`; detailed tables appear below.

| Timing boundary (median per trial) | Baseline | Candidate |
| --- | --- | --- |
| Workflow-stage wall time (includes harness checks) | 19 min 6.7 s | 13 min 13.8 s |
| Independent-judge time | 0 min 13.3 s | 0 min 13.1 s |
Combined medians are reduced from per-trial stage-plus-judge sums, not added component medians.

## Document quality and acceptance

| Measure | Baseline | Candidate |
| --- | --- | --- |
| Document quality (median /100) | 83/100 | 81/100 |
| Functional acceptance | 3 of 3 trials | 3 of 3 trials |
| Full workflow acceptance | 0 of 3 trials | 0 of 3 trials |
| Failed tool calls (total) | 24 | 24 |
| Critical/high findings (total) | 2 | 2 |

Functional acceptance requires every functional probe to pass. **Full workflow acceptance** also requires every stage and the final workflow checks to pass. A successful process exit or final build alone is not full acceptance.

Observed total consumption per accepted workflow: Baseline: Unavailable (0 accepted workflows); Candidate: Unavailable (0 accepted workflows).
This descriptive ratio includes consumption from every recorded attempt, not just successful ones; it is not expected retry cost. Document quality scores assess BRD/PRD content, not delivered software quality. Expert calibration and statistical significance have not been established.

## Comparison findings

- Business clarity scored lower.
- Risks and decisions scored lower.
- Overall quality scored lower.
- Build: State verification passed in fewer trials.
- Initialization: Scribe history passed in fewer trials.
- Requirements: Scribe history passed in fewer trials.
- Stage readiness: Initialization passed in fewer trials.
- Final workflow readiness: State verification passed in fewer trials.

10% resource-improvement screen: **Met.** This requires at least 10% fewer median model requests or input tokens. It is separate from non-regression, product acceptance and strict baseline promotion.

## Checks needing attention

Only checks that did not pass in all three trials are shown here. The complete check list, including passing checks, is available in the details below.

| Check | Baseline | Candidate |
| --- | --- | --- |
| Build: developer | 2 of 3 | 3 of 3 |
| Build: lead | 2 of 3 | 3 of 3 |
| Build: researcher | 2 of 3 | 3 of 3 |
| Build: Review outcome | 2 of 3 | 3 of 3 |
| Build: State verification | 2 of 3 | 1 of 3 |
| Build: tester | 2 of 3 | 3 of 3 |
| Full workflow acceptance | 0 of 3 | 0 of 3 |
| Initialization: Scribe history | 3 of 3 | 1 of 3 |
| Requirements: BRD reviewer deliverable acceptance | 0 of 3 | 2 of 3 |
| Requirements: PRD reviewer deliverable acceptance | 0 of 3 | 2 of 3 |
| Requirements: Review outcome | 0 of 3 | 0 of 3 |
| Requirements: Scribe history | 3 of 3 | 1 of 3 |
| Requirements: State verification | 2 of 3 | 2 of 3 |
| Requirements: tester | 2 of 3 | 2 of 3 |
| Stage readiness: Build | 1 of 3 | 1 of 3 |
| Stage readiness: Initialization | 3 of 3 | 1 of 3 |
| Stage readiness: Requirements | 0 of 3 | 0 of 3 |
| Final workflow readiness | 1 of 3 | 1 of 3 |
| Final workflow readiness: developer | 2 of 3 | 3 of 3 |
| Final workflow readiness: lead | 2 of 3 | 3 of 3 |
| Final workflow readiness: researcher | 2 of 3 | 3 of 3 |
| Final workflow readiness: Review outcome | 2 of 3 | 3 of 3 |
| Final workflow readiness: State verification | 2 of 3 | 1 of 3 |
| Final workflow readiness: tester | 2 of 3 | 3 of 3 |

Reviewer dispatch and reviewer file-deliverable acceptance are different checks. A reviewer may have been dispatched even when its required deliverable check fails.

<details>
<summary>All measurements, samples and checks</summary>

Resource tables use exact values: median [minimum, maximum]; individual samples; series total. Time is in seconds unless explicitly labelled as an event interval in milliseconds; event intervals are diagnostic, not end-to-end timing.

## Combined-resource screening deltas

| Metric | Median absolute change | Change % (positive is worse) |
|---|---|---|
| credits | -45.2169375 | -15.050643662 |
| requests | -81 | -47.647058824 |
| inputTokens | -5230552 | -43.391867181 |
| outputTokens | -123947 | -53.454462337 |
| toolCalls | -155 | -58.270676692 |
| measuredProcessWallSeconds | -353.158 | -30.445390061 |

## workflow resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | 296.4974885 [257.111005, 296.611212]; 296.4974885, 296.611212, 257.111005; 850.2197055 | 251.205051 [243.2490965, 292.510532]; 251.205051, 292.510532, 243.2490965; 786.9646795 |
| requests | 169 [150, 186]; 150, 186, 169; 505 | 88 [84, 103]; 88, 103, 84; 275 |
| inputTokens | 12041694 [10499790, 13467069]; 10499790, 13467069, 12041694; 36008553 | 6809391 [6465424, 7712129]; 6809391, 7712129, 6465424; 20986944 |
| outputTokens | 230962 [198312, 241259]; 198312, 241259, 230962; 670533 | 106996 [106671, 112449]; 106996, 106671, 112449; 326116 |
| toolCalls | 266 [249, 299]; 249, 299, 266; 814 | 111 [101, 116]; 116, 111, 101; 328 |
| failedTools | 9 [5, 10]; 5, 9, 10; 24 | 7 [7, 10]; 7, 10, 7; 24 |
| measuredProcessWallSeconds | 1146.668 [1119.934, 1259.094]; 1146.668, 1259.094, 1119.934; 3525.696 | 793.756 [785.84, 799.427]; 793.756, 785.84, 799.427; 2379.023 |
| cacheReadTokens | 11057738 [9261510, 12362478]; 9261510, 12362478, 11057738; 32681726 | 6236010 [5939434, 7028449]; 6236010, 7028449, 5939434; 19203893 |
| cacheWriteTokens | 1088720 [969535, 1225496]; 1225496, 1088720, 969535; 3283751 | 565857 [518811, 674879]; 565857, 674879, 518811; 1759547 |
| eventElapsedMs | 1142818 [1116506, 1255606]; 1142818, 1255606, 1116506; 3514930 | 790100 [782646, 796050]; 790100, 782646, 796050; 2368796 |

## judge resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | 3.89243 [3.55318, 3.93443]; 3.93443, 3.89243, 3.55318; 11.38004 | 4.83493 [4.00993, 5.61818]; 4.00993, 5.61818, 4.83493; 14.46304 |
| requests | 1 [1, 1]; 1, 1, 1; 3 | 1 [1, 1]; 1, 1, 1; 3 |
| inputTokens | 13981 [12528, 14285]; 14285, 13981, 12528; 40794 | 17595 [14279, 20856]; 14279, 20856, 17595; 52730 |
| outputTokens | 888 [854, 912]; 854, 888, 912; 2654 | 927 [895, 931]; 931, 895, 927; 2753 |
| toolCalls | 0 [0, 0]; 0, 0, 0; 0 | 0 [0, 0]; 0, 0, 0; 0 |
| failedTools | 0 [0, 0]; 0, 0, 0; 0 | 0 [0, 0]; 0, 0, 0; 0 |
| measuredProcessWallSeconds | 13.304 [12.485, 14.068]; 13.304, 12.485, 14.068; 39.857 | 13.058 [12.596, 14.233]; 13.058, 12.596, 14.233; 39.887 |
| cacheReadTokens | 2028 [2028, 2028]; 2028, 2028, 2028; 6084 | 2028 [2028, 2028]; 2028, 2028, 2028; 6084 |
| cacheWriteTokens | 11871 [10418, 12175]; 12175, 11871, 10418; 34464 | 15485 [12169, 18746]; 12169, 18746, 15485; 46400 |
| eventElapsedMs | 10335 [10008, 10714]; 10335, 10008, 10714; 31057 | 10587 [9993, 11683]; 10587, 9993, 11683; 32263 |

## total resources

| Metric | Base median [min, max]; samples; sum | Head median [min, max]; samples; sum |
|---|---|---|
| credits | 300.4319185 [260.664185, 300.503642]; 300.4319185, 300.503642, 260.664185; 861.5997455 | 255.214981 [248.0840265, 298.128712]; 255.214981, 298.128712, 248.0840265; 801.4277195 |
| requests | 170 [151, 187]; 151, 187, 170; 508 | 89 [85, 104]; 89, 104, 85; 278 |
| inputTokens | 12054222 [10514075, 13481050]; 10514075, 13481050, 12054222; 36049347 | 6823670 [6483019, 7732985]; 6823670, 7732985, 6483019; 21039674 |
| outputTokens | 231874 [199166, 242147]; 199166, 242147, 231874; 673187 | 107927 [107566, 113376]; 107927, 107566, 113376; 328869 |
| toolCalls | 266 [249, 299]; 249, 299, 266; 814 | 111 [101, 116]; 116, 111, 101; 328 |
| failedTools | 9 [5, 10]; 5, 9, 10; 24 | 7 [7, 10]; 7, 10, 7; 24 |
| measuredProcessWallSeconds | 1159.972 [1134.002, 1271.579]; 1159.972, 1271.579, 1134.002; 3565.553 | 806.814 [798.436, 813.66]; 806.814, 798.436, 813.66; 2418.91 |
| cacheReadTokens | 11059766 [9263538, 12364506]; 9263538, 12364506, 11059766; 32687810 | 6238038 [5941462, 7030477]; 6238038, 7030477, 5941462; 19209977 |
| cacheWriteTokens | 1100591 [979953, 1237671]; 1237671, 1100591, 979953; 3318215 | 578026 [534296, 693625]; 578026, 693625, 534296; 1805947 |
| eventElapsedMs | 1153153 [1127220, 1265614]; 1153153, 1265614, 1127220; 3545987 | 800687 [792639, 807733]; 800687, 792639, 807733; 2401059 |

## Quality and reliability

| Metric | Base | Head |
|---|---|---|
| quality/businessClarity | 18 [17, 18]; 18, 18, 17 | 17 [15, 17]; 17, 15, 17 |
| quality/scopeFidelity | 17 [17, 18]; 17, 18, 17 | 18 [17, 18]; 18, 18, 17 |
| quality/acceptanceCriteria | 16 [16, 17]; 16, 16, 17 | 16 [16, 17]; 16, 17, 16 |
| quality/traceability | 17 [16, 17]; 17, 17, 16 | 17 [16, 17]; 16, 17, 17 |
| quality/risksAndDecisions | 15 [14, 15]; 15, 14, 15 | 14 [14, 15]; 14, 15, 14 |
| quality/total | 83 [82, 83]; 83, 83, 82 | 81 [81, 82]; 81, 82, 81 |
| criticalHighFindings | 2 | 2 |
| build/consumption-rates.md | 3/3 | 3/3 |
| build/consumption.md | 3/3 | 3/3 |
| build/decisions.md | 3/3 | 3/3 |
| build/developer | 2/3 | 3/3 |
| build/dispatchEvidence | 3/3 | 3/3 |
| build/lead | 2/3 | 3/3 |
| build/researcher | 2/3 | 3/3 |
| build/reviewOutcome | 2/3 | 3/3 |
| build/routing.md | 3/3 | 3/3 |
| build/state.json | 3/3 | 3/3 |
| build/stateVerifier | 2/3 | 1/3 |
| build/team.md | 3/3 | 3/3 |
| build/tester | 2/3 | 3/3 |
| completed | 0/3 | 0/3 |
| functional | 3/3 | 3/3 |
| functional/add-unicode | 3/3 | 3/3 |
| functional/blank-title | 3/3 | 3/3 |
| functional/corrupt-store-preserved | 3/3 | 3/3 |
| functional/done-idempotent | 3/3 | 3/3 |
| functional/empty-list | 3/3 | 3/3 |
| functional/id-boundary-preserves-store | 3/3 | 3/3 |
| functional/invalid-action | 3/3 | 3/3 |
| functional/invalid-filter | 3/3 | 3/3 |
| functional/missing-title | 3/3 | 3/3 |
| functional/persistent-ordered-list | 3/3 | 3/3 |
| functional/status-filter | 3/3 | 3/3 |
| functional/unique-increasing-id | 3/3 | 3/3 |
| functional/unknown-id | 3/3 | 3/3 |
| init/consumption-rates.md | 3/3 | 3/3 |
| init/consumption.md | 3/3 | 3/3 |
| init/decisions.md | 3/3 | 3/3 |
| init/dispatchEvidence | 3/3 | 3/3 |
| init/routing.md | 3/3 | 3/3 |
| init/scribeHistory | 3/3 | 1/3 |
| init/state.json | 3/3 | 3/3 |
| init/stateVerifier | 3/3 | 3/3 |
| init/team.md | 3/3 | 3/3 |
| requirements/BRD Builder | 3/3 | 3/3 |
| requirements/BRD Quality Reviewer | 0/3 | 2/3 |
| requirements/brd.md | 3/3 | 3/3 |
| requirements/consumption-rates.md | 3/3 | 3/3 |
| requirements/consumption.md | 3/3 | 3/3 |
| requirements/decisions.md | 3/3 | 3/3 |
| requirements/dispatchEvidence | 3/3 | 3/3 |
| requirements/PRD Builder | 3/3 | 3/3 |
| requirements/PRD Quality Reviewer | 0/3 | 2/3 |
| requirements/prd.md | 3/3 | 3/3 |
| requirements/reviewOutcome | 0/3 | 0/3 |
| requirements/routing.md | 3/3 | 3/3 |
| requirements/scribeHistory | 3/3 | 1/3 |
| requirements/state.json | 3/3 | 3/3 |
| requirements/stateVerifier | 2/3 | 2/3 |
| requirements/team.md | 3/3 | 3/3 |
| requirements/tester | 2/3 | 2/3 |
| stage/build | 1/3 | 1/3 |
| stage/init | 3/3 | 1/3 |
| stage/requirements | 0/3 | 0/3 |
| workflow | 1/3 | 1/3 |
| workflow/consumption-rates.md | 3/3 | 3/3 |
| workflow/consumption.md | 3/3 | 3/3 |
| workflow/decisions.md | 3/3 | 3/3 |
| workflow/developer | 2/3 | 3/3 |
| workflow/dispatchEvidence | 3/3 | 3/3 |
| workflow/lead | 2/3 | 3/3 |
| workflow/researcher | 2/3 | 3/3 |
| workflow/reviewOutcome | 2/3 | 3/3 |
| workflow/routing.md | 3/3 | 3/3 |
| workflow/state.json | 3/3 | 3/3 |
| workflow/stateVerifier | 2/3 | 1/3 |
| workflow/team.md | 3/3 | 3/3 |
| workflow/tester | 2/3 | 3/3 |
| observed brd reviewer dispatch (not file-deliverable acceptance) | 3/3 | 3/3 |
| observed prd reviewer dispatch (not file-deliverable acceptance) | 3/3 | 3/3 |

</details>

<details>
<summary>Provenance, compatibility and machine status</summary>

Machine status: **regression**; exit code **3**.
Integrity hashes and a reviewed workflow/controller do not authenticate model execution.

| Reference | Value |
|---|---|
| baseCommit | 59880d5c0417e99a7fe6ab5f12670f8bd9b7401b |
| headCommit | 5324132b72a5a2116ce0f7ecf7fc71ed811c8cfa |
| mergeBase | n/a |
| policyHash | adb40d1667d07d653c2875ab18854b88f18ec13278e2338d80d8292e9b4b718c |
| Baseline seriesId | run-20261021-102320-92ef357d |
| Baseline sha256 | d8f8932861e63e03473d9d71a54df086c15a62a3285c414d89d51050d7185f49 |
| Baseline sourceHash | c69a057c35921bd53843bf407f9e135c30f655b6d301c69b9d5fa939b05a3e98 |
| Baseline measuredRevision | 59880d5c0417e99a7fe6ab5f12670f8bd9b7401b |
| Recorded / candidate seriesId | release-1792602314-1-candidate |
| Recorded / candidate sha256 | c399a6401a543b2560e0a268bfc70e59bb6f0dace13d37a94647ad1d44bb4415 |
| Recorded / candidate sourceHash | 655428286888f5f0f81b30937928721b782e4759a27559062b30e00b3ebf2c73 |
| Recorded / candidate measuredRevision | 5324132b72a5a2116ce0f7ecf7fc71ed811c8cfa |

### Baseline protocol

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
| installHash | 529a5170092a87c624a4f63c659781d011c29e64b714ea1498665cc5af564556 |
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

Machine reasons: quality-businessClarity, quality-risksAndDecisions, quality-total, outcome-build/stateVerifier, outcome-init/scribeHistory, outcome-requirements/scribeHistory, outcome-stage/init, outcome-workflow/stateVerifier

</details>
Credits used: 801.4277195 (complete accounting; candidate trials only).
