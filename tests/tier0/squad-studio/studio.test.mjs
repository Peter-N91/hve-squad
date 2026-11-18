// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const STUDIO_ROOT = path.resolve(
    __dirname,
    '../../../squad-src/.github/skills/squad/extensions/hve-squad-studio',
);

const {
    composeHelperBrief,
    composeRefinementLaunch,
    composeStudioLaunch,
    describeRolePlainly,
    detectSuggestedPacks,
} = await import(new URL(`file://${STUDIO_ROOT.replace(/\\/g, '/')}/lib/catalog.mjs`).href);
const { createStudioStore } = await import(
    new URL(`file://${STUDIO_ROOT.replace(/\\/g, '/')}/lib/store.mjs`).href
);
const {
    parseStructuredVerdicts,
    readLiveWorkspaceSnapshot,
    resolveSafeWorkspacePath,
    saveUploadedDocument,
} = await import(
    new URL(`file://${STUDIO_ROOT.replace(/\\/g, '/')}/lib/state-reader.mjs`).href
);
const {
    classifyPendingQuestion,
    createSessionBridge,
    findCoordinatorAgentName,
    pickRecommendedChoice,
} = await import(
    new URL(`file://${STUDIO_ROOT.replace(/\\/g, '/')}/lib/session-bridge.mjs`).href
);
const { createStudioServer } = await import(
    new URL(`file://${STUDIO_ROOT.replace(/\\/g, '/')}/lib/server.mjs`).href
);

test('composeStudioLaunch translates beginner options into displayPrompt and structured HVE Squad prompt', () => {
    const res = composeStudioLaunch({
        goalId: 'web-app',
        goalText: 'Build a friendly booking website for Sunny Crumb Bakery',
        workingStyle: 'guided-auto',
        budgetStyle: 'saver',
        spendingLimitUsd: 5,
        coordinatorSelected: true,
    });

    assert.equal(res.profile, 'product');
    assert.equal(res.sessionMode, 'autopilot');
    assert.match(res.displayPrompt, /^HVE Squad Studio: Build a friendly booking website/);
    assert.match(res.displayPrompt, /Do most of the work for me/);
    assert.match(res.displayPrompt, /Save budget/);
    assert.match(res.displayPrompt, /Limit \$5/);
    assert.match(res.prompt, /- profile: product/);
    assert.match(res.prompt, /- mode: autopilot/);
    assert.match(res.prompt, /- routing: economy/);
    assert.match(res.prompt, /Write-SquadHandoff\.ps1 -Quiet directly/);
    assert.match(res.prompt, /dispatch Scribe only for exit 2 or genuinely cold operations/);
    assert.match(res.prompt, /- cost-ceiling: 5/);
});

test('composeHelperBrief turns 3-click helper choices into a plain-English HVE Squad goal', () => {
    const brief = composeHelperBrief({
        outcomeId: 'shareable-deck',
        audienceId: 'stakeholders',
        readinessId: 'just-an-idea',
        topicNote: 'Community solar initiative',
    });

    assert.equal(brief.goalId, 'slides-deck');
    assert.equal(brief.discovery, 'quick');
    assert.match(brief.goalText, /HVE Squad/);
    assert.match(brief.goalText, /Community solar initiative/);
});

test('findCoordinatorAgentName resolves plugin-qualified and repository agent identifiers', () => {
    assert.equal(
        findCoordinatorAgentName([
            { name: 'hve-squad:squad-coach', displayName: 'Squad Coach' },
            { name: 'hve-squad:squad-coordinator', displayName: 'Squad Coordinator' },
        ]),
        'hve-squad:squad-coordinator',
    );
    assert.equal(
        findCoordinatorAgentName([{ name: 'Squad Coordinator' }]),
        'Squad Coordinator',
    );
    assert.equal(findCoordinatorAgentName([{ name: 'unrelated-agent' }]), null);
});

test('pickRecommendedChoice prefers choices marked (Recommended)', () => {
    const picked = pickRecommendedChoice([
        'Manual setup',
        'Simple form on the page (Recommended)',
    ]);
    assert.equal(picked, 'Simple form on the page (Recommended)');
});

test('readLiveWorkspaceSnapshot projects chosen squad, history deliverables, and blocks path traversal', async () => {
    const tmpRepo = await fs.mkdtemp(path.join(os.tmpdir(), 'hve-squad-studio-ws-'));
    try {
        const squadDir = path.join(tmpRepo, '.copilot-tracking', 'squad');
        const historyDir = path.join(squadDir, 'history');
        const outDir = path.join(tmpRepo, 'outputs');
        await fs.mkdir(historyDir, { recursive: true });
        await fs.mkdir(outDir, { recursive: true });

        await fs.writeFile(
            path.join(squadDir, 'state.json'),
            JSON.stringify({
                schemaVersion: '1.4',
                turn: 2,
                mode: 'autopilot',
                activeRoles: ['Squad Implementor'],
                currentRun: {
                    estCostUsd: 0.25,
                    costPreflight: { ceilingUsd: 5, remainingUsd: 4.75 },
                },
            }),
            'utf8',
        );
        await fs.writeFile(
            path.join(squadDir, 'team.md'),
            '# Squad Team\n\n* **Profile**: `product`\n\n| Member | Role | Agent |\n| --- | --- | --- |\n| Designer | UX | UX UI Designer |\n| Builder | Dev | Squad Implementor |\n',
            'utf8',
        );
        await fs.writeFile(path.join(outDir, 'index.html'), '<!doctype html><title>Bakery</title><h1>Sunny Crumb</h1>', 'utf8');
        await fs.writeFile(
            path.join(historyDir, 'Squad Implementor.md'),
            '# History: Squad Implementor\n\n### 2026-11-14T10:00:00Z Built bakery homepage\n\n* Turn: 2\n* Request: Build homepage\n* Deliverable: `outputs/index.html` (1 KB)\n* Outcome: Created responsive bakery homepage.\n',
            'utf8',
        );

        const snap = await readLiveWorkspaceSnapshot(tmpRepo);
        assert.equal(snap.hasSquadState, true);
        assert.equal(snap.chosenSquad.profileId, 'product');
        assert.equal(snap.chosenSquad.members.length, 2);
        assert.equal(snap.deliverables.length, 1);
        assert.equal(snap.deliverables[0].relativePath, 'outputs/index.html');
        assert.equal(snap.deliverables[0].friendlyType, 'Interactive Web Page');

        await assert.rejects(() => resolveSafeWorkspacePath(tmpRepo, '../outside.txt'));
        await assert.rejects(() => resolveSafeWorkspacePath(tmpRepo, '/etc/passwd'));
    } finally {
        await fs.rm(tmpRepo, { recursive: true, force: true });
    }
});

test('createStudioServer enforces CSRF token, serves CSP headers, and persists preferences across sessions', async () => {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'hve-squad-studio-srv-'));
    const store = createStudioStore({ artifactsDir: tmpDir });
    const bridge = createSessionBridge({
        getSession: () => null,
        onStateChanged: () => {},
        log: () => {},
    });
    const server = await createStudioServer({
        instanceId: 'test-1',
        getSessionKey: () => 'session-abc',
        getRepoRoot: () => tmpDir,
        store,
        bridge,
    });

    try {
        const htmlRes = await fetch(server.url);
        assert.equal(htmlRes.status, 200);
        assert.match(htmlRes.headers.get('content-security-policy') ?? '', /default-src 'none'/);
        const htmlText = await htmlRes.text();
        assert.match(htmlText, /HVE Squad Studio/);
        const tokenMatch = htmlText.match(/data-csrf-token="([a-f0-9]+)"/);
        assert.ok(tokenMatch, 'CSRF token must be embedded in document root');
        const token = tokenMatch[1];

        const forbidden = await fetch(`${server.url}api/preferences`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ neverAutoOpen: true }),
        });
        assert.equal(forbidden.status, 403);

        const allowed = await fetch(`${server.url}api/preferences`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Studio-Token': token,
            },
            body: JSON.stringify({ neverAutoOpen: true, theme: 'dark' }),
        });
        assert.equal(allowed.status, 200);
        const prefJson = await allowed.json();
        assert.equal(prefJson.preferences.neverAutoOpen, true);
        assert.equal(prefJson.preferences.theme, 'dark');

        // Verify composeRefinementLaunch and role translation stay jargon-free
        const ref = composeRefinementLaunch({ refinementId: 'visual-polish', details: 'Warmer colors' });
        assert.match(ref.displayPrompt, /HVE Squad Studio/);
        assert.equal(describeRolePlainly('Squad Coordinator').friendlyName, 'HVE Squad Coordinator');

        // Verify document upload over HTTP + auto-detected pack suggestion
        const uploadRes = await fetch(`${server.url}api/upload`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Studio-Token': token,
            },
            body: JSON.stringify({
                fileName: 'teams-catering-spec.md',
                base64Content: Buffer.from('Build a SharePoint and Microsoft 365 catering portal.').toString('base64'),
            }),
        });
        assert.equal(uploadRes.status, 200);
        const uploadJson = await uploadRes.json();
        assert.equal(uploadJson.state.draft.uploadedFiles.length, 1);
        assert.ok(
            uploadJson.state.suggestedPacks.some((p) => p.id === 'm365-copilot'),
            'Should auto-suggest m365-copilot pack from uploaded document text',
        );
    } finally {
        await server.close();
        await fs.rm(tmpDir, { recursive: true, force: true });
    }
});

test('predefined init, intake document upload, pack preview guardrails, and council checkups compose cleanly', async () => {
    const tmpRepo = await fs.mkdtemp(path.join(os.tmpdir(), 'hve-squad-studio-intake-'));
    try {
        const savedDoc = await saveUploadedDocument(tmpRepo, {
            fileName: 'catering-requirements.md',
            base64Content: Buffer.from('# Requirements\nPower Apps order screen with Dataverse.').toString('base64'),
        });
        assert.equal(savedDoc.relativePath, '.copilot-tracking/studio-inputs/catering-requirements.md');

        const suggested = detectSuggestedPacks('', [savedDoc]);
        assert.equal(suggested[0]?.id, 'power-platform');
        assert.ok(
            detectSuggestedPacks('Review FinOps Azure cost guardrails and Azure Local sizing').some(
                (pack) => pack.id === 'azure-cloud',
            ),
        );

        const launch = composeStudioLaunch({
            goalId: 'docs-report',
            goalText: 'Build the catering order workflow from my attached notes',
            selectedPacks: ['power-platform'],
            allowPackPreviews: false,
            requestCouncilCheckup: true,
            validateIntake: true,
            uploadedFiles: [savedDoc],
            coordinatorSelected: true,
            preSeeded: false,
        });

        assert.equal(launch.profile, 'product', 'Uploaded docs with intake checkup ensure intake-validator profile');
        assert.deepEqual(launch.packs, ['power-platform']);
        assert.match(launch.prompt, /- pack: power-platform/);
        assert.match(launch.prompt, /- inputs: \.copilot-tracking\/studio-inputs\/catering-requirements\.md/);
        assert.match(launch.prompt, /layout: single/);
        assert.match(launch.prompt, /naming: skip/);
        assert.match(launch.prompt, /"approvalChannel":"in-chat","enabled":false/);
        assert.match(launch.prompt, /NOT approved \(use core stable pack skills only/);
        assert.match(launch.prompt, /intakeValidation:/);
        assert.match(launch.prompt, /preBuildCheckup:/);

        const verdicts = parseStructuredVerdicts(`# Squad Decisions

## Intake Readiness Verdict 2026-11-14T12:00:00Z catering

* Topic: Catering workflow
* Inputs Reviewed: .copilot-tracking/studio-inputs/catering-requirements.md
* Validator Dispatched: PRD Quality Reviewer
* Verdict: Ready-With-Gaps
* Remediation Cycles: 0

### Findings

| Dimension | Result | Blocking Gaps | Non-Blocking Gaps |
| --- | --- | --- | --- |
| Completeness | pass | none | Assumed single store |
| Clarity | pass | none | none |

## Council Waiver 2026-11-14T12:05:00Z catering
* Decision: waived by user
`);
        assert.equal(verdicts.intakeCheckup?.verdict, 'Ready-With-Gaps');
        assert.equal(verdicts.intakeCheckup?.dimensions.length, 2);
        assert.equal(verdicts.councilCheckup?.verdict, 'Waived');

        const councilQ = classifyPendingQuestion(
            'Propose task-fit council (architect, security, cost-manager) or waive?',
            ['Approve council (Recommended)', 'Skip and waive council'],
        );
        assert.equal(councilQ.kind, 'council');
        assert.equal(councilQ.skipChoice, 'Skip and waive council');
    } finally {
        await fs.rm(tmpRepo, { recursive: true, force: true });
    }
});
