# Squad Live Benchmark Report

Generated 2026-10-06 07:53 from `results.csv`: 27 scored runs, levels easy, medium, hard, arms B, R, E.

Arms: **B** baseline source with default routing; **R** candidate source with `routing=ranked`; **E** candidate source with `routing=economy`. Credits are `totalNanoAiu / 1e9` from the CLI usage file (runtime credits, not reconciled billing). Cells show median [min, max].

| Arm | Session models | CLI versions | Source tree hashes |
| --- | --- | --- | --- |
| B | gpt-6-luna | GitHub Copilot CLI 1.0.92-5., GitHub Copilot CLI 1.0.92. | 3B3751370965 |
| R | gpt-6-luna | GitHub Copilot CLI 1.0.92-5., GitHub Copilot CLI 1.0.92. | E70BD58D3BAE |
| E | gpt-6-luna | GitHub Copilot CLI 1.0.92-5., GitHub Copilot CLI 1.0.92. | E70BD58D3BAE |

## Speed and Cost

| Level | Arm | n | Seconds | Credits | Coordinator cr | Owner cr | Input tokens (k) | Output tokens (k) | Cache-read tokens (k) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| easy | B | 3 | 1981 [879, 2677] | 221.5 [95, 330.3] | 7.7 [5.4, 12.9] | 60.3 [21.4, 80.7] | 12507 [6087, 20226] | 137 [69, 216] | 11920 [5756, 19397] |
| easy | R | 3 | 1375 [384, 1649] | 162.7 [38.1, 166.8] | 5 [2.3, 7.8] | 14.9 [0, 16] | 8755 [2378, 9228] | 100 [29, 134] | 8291 [2201, 8799] |
| easy | E | 3 | 891 [658, 992] | 68.8 [49.4, 102.1] | 5 [4.4, 5.2] | 7.9 [7.6, 8.9] | 4320 [3197, 5720] | 67 [50, 75] | 4112 [2948, 5375] |
| medium | B | 3 | 580 [83, 3350] | 42.9 [1.1, 463.5] | 3.4 [1.1, 12.2] | 13.8 [0, 120.4] | 2407 [229, 26503] | 34 [7, 267] | 2182 [179, 25343] |
| medium | R | 3 | 1043 [729, 1386] | 108 [70.6, 137.1] | 8 [5.3, 9.2] | 40.6 [22.8, 50] | 6384 [3903, 8371] | 88 [68, 120] | 6048 [3658, 7976] |
| medium | E | 3 | 1586 [643, 1603] | 156.2 [67.1, 200.1] | 6.2 [3, 10.1] | 22.6 [17.4, 28.8] | 9886 [3540, 10214] | 137 [65, 138] | 9306 [3361, 9694] |
| hard | B | 3 | 2076 [860, 2860] | 287.6 [119.7, 415.4] | 7.2 [4.8, 9.6] | 125.2 [78.5, 188.2] | 12995 [4823, 18456] | 167 [74, 228] | 12288 [4492, 17511] |
| hard | R | 3 | 3239 [1907, 3736] | 489 [204.6, 587.7] | 14.6 [8.7, 16.9] | 200.7 [57.5, 251.8] | 22339 [10322, 25845] | 241 [133, 305] | 21248 [9871, 24673] |
| hard | E | 3 | 1441 [1042, 2426] | 179.6 [135.3, 318.7] | 6.1 [5.8, 12.2] | 62.8 [29.8, 152.7] | 9230 [5772, 12609] | 108 [93, 196] | 8737 [5419, 11817] |

## Paired Differences vs B

Each row pairs an arm with the B run of the same level and repeat. Negative is faster or cheaper than B.

| Level | Repeat | Arm | Δ seconds | Δ credits | Δ coordinator cr | Δ owner cr | Δ hidden passed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| easy | 1 | R | -495 | -57 | -3.2 | -21.4 | 0 |
| easy | 1 | E | +113 | +7 | -0.5 | -13.7 | +5 |
| easy | 2 | R | -1302 | -163.5 | -7.8 | -64.8 | 0 |
| easy | 2 | E | -2019 | -280.9 | -7.6 | -71.8 | 0 |
| easy | 3 | R | -332 | -58.7 | +0 | -45.4 | 0 |
| easy | 3 | E | -1090 | -152.6 | -3.3 | -52.4 | 0 |
| medium | 1 | R | +960 | +106.9 | +6.9 | +50 | +7 |
| medium | 1 | E | +1503 | +155.1 | +8.9 | +22.6 | +7 |
| medium | 2 | R | -1964 | -326.4 | -3.1 | -79.9 | 0 |
| medium | 2 | E | -2707 | -396.4 | -9.2 | -103 | 0 |
| medium | 3 | R | +149 | +27.6 | +1.8 | +9.1 | +7 |
| medium | 3 | E | +1023 | +157.2 | +2.7 | +15 | +7 |
| hard | 1 | R | -953 | -210.8 | -0.9 | -130.8 | 0 |
| hard | 1 | E | -434 | -96.6 | +2.6 | -35.5 | 0 |
| hard | 2 | R | +2876 | +467.9 | +12.1 | +173.3 | +12 |
| hard | 2 | E | +182 | +15.6 | +1.3 | -15.7 | 0 |
| hard | 3 | R | +1163 | +201.4 | +7.3 | +75.5 | 0 |
| hard | 3 | E | -635 | -108 | -1.5 | -95.4 | 0 |

| Level | Arm | Pairs | Median Δ seconds | Pairs faster | Median Δ credits | Pairs cheaper |
| --- | --- | --- | --- | --- | --- | --- |
| easy | E | 3 | -1090 | 2/3 | -152.6 | 2/3 |
| easy | R | 3 | -495 | 3/3 | -58.7 | 3/3 |
| hard | E | 3 | -434 | 2/3 | -96.6 | 2/3 |
| hard | R | 3 | +1163 | 1/3 | +201.4 | 1/3 |
| medium | E | 3 | +1023 | 1/3 | +155.1 | 1/3 |
| medium | R | 3 | +149 | 1/3 | +27.6 | 1/3 |

## Quality

| Level | Arm | Outcomes | Hidden tests passed | All hidden pass | Own tests pass | Own tests pass on reference | Mutants killed by own tests | Doc check | Review verdicts | Ledger -Check | Judge mean |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| easy | B | dispatched x3 | 13/18 | 2/3 | 3/3 | 3/3 | 6/9 | n/a | none x1, Pass x2 | PASS x3 | not judged |
| easy | R | dispatched x2, halted x1 | 13/18 | 2/3 | 3/3 | 3/3 | 6/9 | n/a | none x1, Pass x2 | PASS x3 | not judged |
| easy | E | dispatched x3 | 18/18 | 3/3 | 3/3 | 3/3 | 9/9 | n/a | Pass x3 | PASS x3 | not judged |
| medium | B | dispatched x2, halted x1 | 19/33 | 1/3 | 3/3 | 3/3 | 2/6 | 1/3 | none x2, Pass x1 | PASS x3 | not judged |
| medium | R | dispatched x3 | 33/33 | 3/3 | 3/3 | 1/3 | 2/6 | 3/3 | Pass x3 | PASS x3 | not judged |
| medium | E | dispatched x3 | 33/33 | 3/3 | 3/3 | 2/3 | 4/6 | 3/3 | none x1, Pass x2 | PASS x3 | not judged |
| hard | B | dispatched x3 | 27/39 | 2/3 | 3/3 | 2/3 | 3/12 | 2/3 | none x1, Pass x2 | PASS x3 | not judged |
| hard | R | dispatched x3 | 39/39 | 3/3 | 3/3 | 0/3 | 0/12 | 3/3 | Fail x1, Pass x1, Pass-With-Findings x1 | PASS x3 | not judged |
| hard | E | dispatched x3 | 27/39 | 2/3 | 3/3 | 1/3 | 0/12 | 2/3 | none x1, Pass x2 | PASS x3 | not judged |

## Model Assignment

`Model cell` is the `team.md` Model column (present only under ranked, economy, or manual routing). `Passed` is the model the coordinator passed on the `task` dispatch. `Match` compares the cell with the model the agent actually ran on.

| Level | Arm | Role | Agent | Runs | Models used | Model cell | Passed | Match | Credits |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| easy | B | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 7.7 [5.4, 12.9] |
| easy | B | developer | Squad Implementor | 2 | claude-sonnet-5 x2 |  |  | n/a x2 | 19.2 [16.5, 22] |
| easy | B | lead | Squad Lead | 2 | claude-sonnet-5 x2 |  |  | n/a x2 | 27.9 [25.2, 30.5] |
| easy | B | researcher | Squad Researcher | 3 | claude-sonnet-5 x3 |  |  | n/a x3 | 21.4 [18.6, 28.3] |
| easy | B | scribe | Squad Scribe | 16 | claude-haiku-4.5 x16 |  |  | n/a x16 | 25.2 [7, 67.3] |
| easy | B | tester | Squad Reviewer | 2 | claude-haiku-4.5 x2 |  |  | n/a x2 | 8 [7.8, 8.1] |
| easy | R | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 5 [2.3, 7.8] |
| easy | R | developer | Squad Implementor | 4 | gpt-5.3-codex x4 | gpt-5.3-codex x4 | gpt-5.3-codex x4 | yes x4 | 7.8 [7, 8.2] |
| easy | R | scribe | Squad Scribe | 16 | claude-haiku-4.5 x16 | claude-haiku-4.5 x16 |  | yes x16 | 17.9 [3, 26.8] |
| easy | R | tester | Squad Reviewer | 4 | gpt-6-sol x4 | gpt-6-sol x4 | gpt-6-sol x4 | yes x4 | 15.2 [12.4, 16.4] |
| easy | E | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 5 [4.4, 5.2] |
| easy | E | developer | Squad Implementor | 3 | gpt-5.3-codex x3 | gpt-5.3-codex x3 | gpt-5.3-codex x3 | yes x3 | 7.9 [7.6, 8.9] |
| easy | E | scribe | Squad Scribe | 10 | claude-haiku-4.5 x10 | claude-haiku-4.5 x10 |  | yes x10 | 12.7 [3.7, 24.5] |
| easy | E | tester | Squad Reviewer | 3 | gpt-6-sol x3 | gpt-6-sol x3 | gpt-6-sol x3 | yes x3 | 12.9 [8.1, 17.2] |
| medium | B | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 3.4 [1.1, 12.2] |
| medium | B | developer | Squad Implementor | 1 | claude-sonnet-5 x1 |  |  | n/a x1 | 27.9 |
| medium | B | lead | Squad Lead | 1 | claude-sonnet-5 x1 |  |  | n/a x1 | 28 |
| medium | B | researcher | Squad Researcher | 2 | claude-sonnet-5 x2 |  |  | n/a x2 | 20.7 [13.8, 27.6] |
| medium | B | scribe | Squad Scribe | 12 | claude-haiku-4.5 x12 |  |  | n/a x12 | 25.1 [11.8, 50.2] |
| medium | B | technical-writer | Squad Technical Writer | 4 | claude-haiku-4.5 x4 |  |  | n/a x4 | 9.3 [4.3, 14.1] |
| medium | B | tester | Squad Reviewer | 2 | claude-haiku-4.5 x2 |  |  | n/a x2 | 9.4 [9.4, 9.5] |
| medium | R | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 8 [5.3, 9.2] |
| medium | R | developer | Squad Implementor | 8 | gpt-5.3-codex x8 | gpt-5.3-codex x8 | gpt-5.3-codex x8 | yes x8 | 8.6 [6.5, 12.1] |
| medium | R | scribe | Squad Scribe | 16 | claude-haiku-4.5 x16 | claude-haiku-4.5 x16 | claude-haiku-4.5 x9 | yes x16 | 5.7 [2.4, 21.1] |
| medium | R | technical-writer | Squad Technical Writer | 4 | gpt-5.3-codex x4 | gpt-5.3-codex x4 | gpt-5.3-codex x4 | yes x4 | 9.7 [7.2, 14] |
| medium | R | tester | Squad Reviewer | 5 | gpt-6-sol x5 | gpt-6-sol x5 | gpt-6-sol x5 | yes x5 | 9.6 [8.2, 11.6] |
| medium | E | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 6.2 [3, 10.1] |
| medium | E | developer | Squad Implementor | 7 | gpt-5.3-codex x7 | gpt-5.3-codex x7 | gpt-5.3-codex x7 | yes x7 | 7.8 [5.9, 10] |
| medium | E | scribe | Squad Scribe | 15 | claude-haiku-4.5 x15 | claude-haiku-4.5 x15 |  | yes x15 | 17.9 [10, 29.2] |
| medium | E | technical-writer | Squad Technical Writer | 3 | gpt-5.4-mini x3 | gpt-5.4-mini x3 | gpt-5.4-mini x3 | yes x3 | 4.1 [3.8, 5.5] |
| medium | E | tester | Squad Reviewer | 3 | gpt-6-sol x3 | gpt-6-sol x3 | gpt-6-sol x3 | yes x3 | 12.9 [10.6, 15.8] |
| hard | B | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 7.2 [4.8, 9.6] |
| hard | B | developer | Squad Implementor | 3 | claude-sonnet-5 x3 |  |  | n/a x3 | 31 [22.7, 55.2] |
| hard | B | lead | Squad Lead | 4 | claude-sonnet-5 x4 |  |  | n/a x4 | 37.5 [34.9, 46.1] |
| hard | B | researcher | Squad Researcher | 3 | claude-sonnet-5 x3 |  |  | n/a x3 | 41.1 [26.7, 49.4] |
| hard | B | scribe | Squad Scribe | 18 | claude-haiku-4.5 x18 |  |  | n/a x18 | 20.2 [10.1, 29.6] |
| hard | B | technical-writer | Squad Technical Writer | 2 | claude-haiku-4.5 x2 |  |  | n/a x2 | 4.9 [3.6, 6.3] |
| hard | B | tester | Squad Reviewer | 4 | claude-haiku-4.5 x4 |  |  | n/a x4 | 15.6 [3.2, 20.1] |
| hard | R | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 14.6 [8.7, 16.9] |
| hard | R | developer | Squad Implementor | 7 | gpt-5.3-codex x7 | gpt-5.3-codex x7 | gpt-5.3-codex x7 | yes x7 | 22.7 [15.7, 31.4] |
| hard | R | lead | Squad Lead | 4 | gpt-5.6-sol x4 | gpt-5.6-sol x4 | gpt-5.6-sol x4 | yes x4 | 40.1 [18.3, 42.3] |
| hard | R | researcher | Squad Researcher | 2 | claude-opus-5.5 x2 | claude-opus-5.5 x2 | claude-opus-5.5 x2 | yes x2 | 60.6 [59.2, 62] |
| hard | R | scribe | Squad Scribe | 35 | claude-haiku-4.5 x35 | claude-haiku-4.5 x35 | claude-haiku-4.5 x14 | yes x35 | 13.6 [3.6, 63] |
| hard | R | technical-writer | Squad Technical Writer | 6 | gpt-5.3-codex x6 | gpt-5.3-codex x6 | gpt-5.3-codex x6 | yes x6 | 13 [9.2, 19.3] |
| hard | R | tester | Squad Reviewer | 7 | gpt-6-sol x7 | gpt-6-sol x7 | gpt-6-sol x7 | yes x7 | 24 [19.4, 36.7] |
| hard | E | coordinator | coordinator | 3 | gpt-6-luna x3 |  |  | n/a x3 | 6.1 [5.8, 12.2] |
| hard | E | developer | Squad Implementor | 4 | gpt-5.3-codex x4 | gpt-5.3-codex x4 | gpt-5.3-codex x4 | yes x4 | 17.6 [14.6, 21.2] |
| hard | E | lead | Squad Lead | 1 | gpt-5.6-sol x1 | gpt-5.6-sol x1 | gpt-5.6-sol x1 | yes x1 | 41.4 |
| hard | E | researcher | Squad Researcher | 2 | claude-opus-5.5 x2 | claude-opus-5.5 x2 | claude-opus-5.5 x2 | yes x2 | 62.2 [61.6, 62.8] |
| hard | E | scribe | Squad Scribe | 20 | claude-haiku-4.5 x20 | Claude Haiku 4.5 x9, claude-haiku-4.5 x11 |  | no x9, yes x11 | 14.6 [4.2, 25.5] |
| hard | E | technical-writer | Squad Technical Writer | 2 | gpt-5.4-mini x2 | gpt-5.4-mini x2 | gpt-5.4-mini x2 | yes x2 | 4.4 [2.7, 6] |
| hard | E | tester | Squad Reviewer | 4 | gpt-6-sol x4 | gpt-6-sol x4 | gpt-6-sol x4 | yes x4 | 16.2 [11.1, 23.5] |

## Process Signals

| Level | Arm | Routing recorded | Model cells match | Top-level dispatches | Scribe dispatches | Generic-agent dispatches | Brief ran | Coordinator ran hand-off script | Hand-off seconds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| easy | B | off x3 | n/a x3 | 10 [3, 12] | 6 [2, 8] | 0 | 0/3 | 0 [0, 0] | 700 [223, 1176] |
| easy | R | ranked x3 | 11/11 x2, 2/2 x1 | 11 [2, 11] | 7 [2, 7] | 0 | 3/3 | 0 [0, 0] | 224 [211, 237] |
| easy | E | economy x3 | 5/5 x2, 6/6 x1 | 5 [5, 6] | 3 [3, 4] | 0 | 3/3 | 0 [0, 0] | 206 [176, 248] |
| medium | B | off x3 | n/a x3 | 2 [0, 20] | 1 [0, 11] | 0 | 0/3 | 0 [0, 0] | 419 |
| medium | R | ranked x3 | 11/11 x1, 15/15 x1, 7/7 x1 | 11 [7, 15] | 4 [3, 9] | 0 | 3/3 | 0 [0, 0] | 212 [137, 856] |
| medium | E | economy x3 | 10/10 x1, 13/13 x1, 5/5 x1 | 10 [5, 13] | 6 [2, 7] | 0 | 3/3 | 0 [0, 0] | 346 [282, 411] |
| hard | B | off x3 | n/a x3 | 12 [4, 18] | 6 [2, 10] | 0 | 0/3 | 0 [0, 0] | 334 [272, 395] |
| hard | R | ranked x3 | 13/13 x1, 24/24 x2 | 24 [13, 26] | 14 [7, 16] | 0 | 3/3 | 0 [0, 0] | 166 [88, 374] |
| hard | E | economy x3 | 10/10 x1, 6/6 x1, 8/17 x1 | 10 [6, 17] | 6 [5, 9] | 0 | 3/3 | 0 [0, 0] | 206 [180, 232] |

## Limitations

* **Sample size.** 3 to 3 runs per level and arm. Medians, ranges, and paired differences describe these runs only; no p-values or confidence intervals are claimed, and a difference smaller than the within-arm range is not evidence of an effect.
* **Warm cache and shared quota.** Runs execute back to back on one account, so prompt-cache warmth and service load vary with position; counterbalanced arm order spreads this across arms but does not remove it.
* **Single fixture, single language.** Every level is a change to one small Python inventory ledger. Results may not transfer to larger repositories, other languages, or tasks that need research or planning.
* **Source overlay.** Each arm overlays its squad-src onto a fresh fixture without a full APM install or hve-core, and every arm starts from the same seeded team.md and consumption-rates.md.
* **Runtime credits.** Credits come from the CLI usage file and are not reconciled against billing.
* **Quality proxies.** Hidden tests and mutants check the specified behaviour only. The blind judge is one model, one session per level, grading anonymised diffs; redaction removes arm labels, run ids, paths, model ids and routing tokens, but writing style could still leak.
