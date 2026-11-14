// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

import fs from 'node:fs/promises';
import path from 'node:path';

import { describeProfilePlainly, describeRolePlainly, PACK_CARDS } from './catalog.mjs';

const MAX_READ_BYTES = 128 * 1024;
export const MAX_UPLOAD_FILE_BYTES = 8 * 1024 * 1024;
export const UPLOAD_ALLOWED_EXTENSIONS = new Set([
    '.md', '.txt', '.docx', '.pdf', '.pptx', '.xlsx', '.csv', '.json', '.yml', '.yaml', '.html', '.htm',
]);
const TEXT_EXTENSIONS = new Set(['.md', '.txt', '.html', '.htm', '.css', '.js', '.mjs', '.json', '.yml', '.yaml', '.csv']);

async function statSafe(target) {
    try {
        return await fs.lstat(target);
    } catch {
        return null;
    }
}

/**
 * Resolves a workspace-relative path safely without traversing outside `repoRoot`
 * or following symbolic links / reparse points.
 *
 * @param {string} repoRoot
 * @param {string} relativePath
 */
export async function resolveSafeWorkspacePath(repoRoot, relativePath) {
    if (typeof relativePath !== 'string' || !relativePath.trim()) {
        throw new Error('File path is required.');
    }
    const normalizedInput = relativePath.trim().replace(/\\/g, '/');
    if (normalizedInput.startsWith('/') || /^[A-Za-z]:/.test(normalizedInput) || normalizedInput.split('/').includes('..')) {
        throw new Error('Path must stay inside the current project folder.');
    }

    const rootResolved = path.resolve(repoRoot);
    const targetResolved = path.resolve(rootResolved, normalizedInput);
    const rel = path.relative(rootResolved, targetResolved);
    if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) {
        throw new Error('Path leaves the project folder.');
    }

    let cursor = rootResolved;
    for (const part of rel.split(path.sep)) {
        cursor = path.join(cursor, part);
        const st = await statSafe(cursor);
        if (st && st.isSymbolicLink()) {
            throw new Error('Symbolic links are not read by HVE Squad Studio.');
        }
    }
    return { fullPath: targetResolved, relativePath: rel.replace(/\\/g, '/') };
}

async function readSmallText(repoRoot, relativePath) {
    try {
        const { fullPath } = await resolveSafeWorkspacePath(repoRoot, relativePath);
        const st = await statSafe(fullPath);
        if (!st || !st.isFile() || st.size > MAX_READ_BYTES) return null;
        return await fs.readFile(fullPath, 'utf8');
    } catch {
        return null;
    }
}

/**
 * Saves an uploaded requirement/input document safely into `.copilot-tracking/studio-inputs/`
 * so HVE Squad can run its Intake Gate against it without polluting `.copilot-tracking/squad/`.
 *
 * @param {string} repoRoot
 * @param {{ fileName: string, base64Content: string }} payload
 */
export async function saveUploadedDocument(repoRoot, payload) {
    if (!repoRoot) throw new Error('Open a project folder before attaching a document.');
    const rawName = path.basename(String(payload?.fileName ?? '').trim());
    const ext = path.extname(rawName).toLowerCase();
    if (!rawName || !UPLOAD_ALLOWED_EXTENSIONS.has(ext)) {
        throw new Error(
            'Supported file types: Word (.docx), PDF (.pdf), PowerPoint (.pptx), Excel/CSV (.xlsx, .csv), Markdown (.md), Text (.txt), JSON/YAML, or HTML.',
        );
    }

    const b64 = String(payload?.base64Content ?? '').trim();
    if (!b64) throw new Error('Uploaded file appears to be empty.');
    const buffer = Buffer.from(b64, 'base64');
    if (buffer.length === 0) throw new Error('Uploaded file appears to be empty.');
    if (buffer.length > MAX_UPLOAD_FILE_BYTES) {
        throw new Error('Each attached document must be 8 MB or smaller.');
    }

    const stem = path.basename(rawName, ext).replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 64) || 'document';
    const safeFileName = `${stem}${ext}`;
    const relativePath = `.copilot-tracking/studio-inputs/${safeFileName}`;
    const { fullPath } = await resolveSafeWorkspacePath(repoRoot, relativePath);

    await fs.mkdir(path.dirname(fullPath), { recursive: true });
    const dirStat = await statSafe(path.dirname(fullPath));
    if (!dirStat || dirStat.isSymbolicLink()) {
        throw new Error('Refusing to write to a linked directory.');
    }

    await fs.writeFile(fullPath, buffer);

    let excerpt = '';
    if (TEXT_EXTENSIONS.has(ext)) {
        excerpt = buffer
            .subarray(0, 4096)
            .toString('utf8')
            .replace(/\s+/g, ' ')
            .trim()
            .slice(0, 360);
    }

    return {
        relativePath,
        originalName: rawName,
        sizeBytes: buffer.length,
        excerpt,
    };
}

/**
 * Removes a previously uploaded file confined strictly under `.copilot-tracking/studio-inputs/`.
 *
 * @param {string} repoRoot
 * @param {string} relativePath
 */
export async function removeUploadedDocument(repoRoot, relativePath) {
    const { fullPath, relativePath: safeRel } = await resolveSafeWorkspacePath(repoRoot, relativePath);
    if (!safeRel.startsWith('.copilot-tracking/studio-inputs/')) {
        throw new Error('Only studio-uploaded input files can be removed here.');
    }
    await fs.rm(fullPath, { force: true });
    return { removed: safeRel };
}

/**
 * Parses `team.md` to extract the chosen squad profile, active packs, and friendly member cards.
 *
 * @param {string | null} teamMarkdown
 */
export function parseTeamMarkdown(teamMarkdown) {
    if (!teamMarkdown) {
        return { profileId: null, profileTitle: 'Not chosen yet', activePacks: [], members: [] };
    }
    const profileMatch = teamMarkdown.match(/^\s*(?:\*\s*)?(?:\*\*Profile\*\*|Profile)\s*[:—-]\s*`?([a-z0-9-]+)`?/im);
    const profileId = profileMatch ? profileMatch[1].toLowerCase() : 'default';

    const packsMatch = teamMarkdown.match(/^\s*(?:\*\s*)?(?:\*\*Packs\*\*|Packs)\s*[:—-]\s*(.+)$/im);
    const activePacks = packsMatch
        ? packsMatch[1]
            .split(/[,+]/)
            .map((s) => s.replace(/`/g, '').trim().toLowerCase())
            .filter((s) => s && s !== 'none' && s !== '—')
            .map((id) => ({
                id,
                title: PACK_CARDS.find((p) => p.id === id)?.title ?? id,
            }))
        : [];

    const members = [];
    const seen = new Set();
    for (const line of teamMarkdown.split(/\r?\n/)) {
        if (!line.trim().startsWith('|')) continue;
        const cells = line.split('|').slice(1, -1).map((c) => c.trim());
        if (cells.length < 2) continue;
        const first = cells[0].replace(/`/g, '');
        if (!first || /^[-:]+$/.test(first) || /^(member|role|name)$/i.test(first)) continue;
        const candidateAgent = (cells[2] || cells[1] || first).replace(/`/g, '').trim();
        const roleInfo = describeRolePlainly(candidateAgent);
        if (seen.has(roleInfo.friendlyName)) continue;
        seen.add(roleInfo.friendlyName);
        members.push(roleInfo);
    }

    return {
        profileId,
        profileTitle: describeProfilePlainly(profileId),
        activePacks,
        members: members.slice(0, 12),
    };
}

/**
 * Parses structured Intake Readiness and Council / Council Waiver verdicts from `decisions.md`.
 *
 * @param {string | null} decisionsMarkdown
 */
export function parseStructuredVerdicts(decisionsMarkdown) {
    if (!decisionsMarkdown) {
        return { intakeCheckup: null, councilCheckup: null };
    }

    let intakeCheckup = null;
    let councilCheckup = null;
    const sections = decisionsMarkdown.split(/^##\s+/m).slice(1);

    for (const raw of sections) {
        const heading = (raw.split(/\r?\n/)[0] ?? '').trim();

        if (/^Intake Readiness Verdict\b/i.test(heading)) {
            const verdictMatch = raw.match(/^\*\s*Verdict:\s*(Ready-With-Gaps|Not-Ready|Ready)\b/im);
            const inputsMatch = raw.match(/^\*\s*Inputs Reviewed:\s*(.+)$/im);
            const verdict = verdictMatch ? verdictMatch[1] : 'Ready';
            const dimensions = [];
            for (const line of raw.split(/\r?\n/)) {
                if (!line.trim().startsWith('|')) continue;
                const cells = line.split('|').slice(1, -1).map((c) => c.trim());
                if (cells.length < 4 || /^[-:]+$/.test(cells[0]) || /^dimension$/i.test(cells[0])) continue;
                const passed = /pass/i.test(cells[1]);
                const gapNote = !passed && cells[2] && !/^none$/i.test(cells[2])
                    ? cells[2]
                    : (cells[3] && !/^none$/i.test(cells[3]) ? cells[3] : 'Looks clear');
                dimensions.push({
                    name: cells[0],
                    passed,
                    note: gapNote,
                });
            }
            intakeCheckup = {
                verdict,
                friendlyTitle: verdict === 'Ready'
                    ? 'Document Checkup: Ready to Build'
                    : verdict === 'Ready-With-Gaps'
                        ? 'Document Checkup: Ready (helpful assumptions noted)'
                        : 'Document Checkup: Needs one quick detail from you',
                inputsReviewed: inputsMatch ? inputsMatch[1].trim() : 'Attached document',
                dimensions,
            };
        } else if (/^Council Verdict\b/i.test(heading)) {
            const verdictMatch = raw.match(/^\*\s*Verdict:\s*(Go-With-Conditions|Stop|Go)\b/im);
            const membersMatch = raw.match(/^\*\s*Council Members Dispatched:\s*(.+)$/im);
            const condMatch = raw.match(/^\*\s*Conditions:\s*(.+)$/im);
            const verdict = verdictMatch ? verdictMatch[1] : 'Go';
            councilCheckup = {
                verdict,
                friendlyTitle: verdict === 'Go'
                    ? 'Pre-Build Safety & Design Checkup: Approved'
                    : verdict === 'Go-With-Conditions'
                        ? 'Pre-Build Checkup: Approved with helpful guardrails'
                        : 'Pre-Build Checkup: Paused — needs your review',
                members: membersMatch ? membersMatch[1].trim() : 'Task-fit specialists',
                note: condMatch && !/^none$/i.test(condMatch[1].trim())
                    ? condMatch[1].trim()
                    : 'Safety, structure, and budget checks passed.',
            };
        } else if (/^Council Waiver\b/i.test(heading)) {
            councilCheckup = {
                verdict: 'Waived',
                friendlyTitle: 'Pre-Build Extra Checkup: Skipped by your choice',
                members: 'Waived',
                note: 'Recorded cleanly so your chosen squad can keep building without delay.',
            };
        }
    }

    return { intakeCheckup, councilCheckup };
}

/**
 * Parses `decisions.md` headings and first summary lines into plain-English cards.
 *
 * @param {string | null} decisionsMarkdown
 */
export function parseDecisionsMarkdown(decisionsMarkdown) {
    if (!decisionsMarkdown) return [];
    const entries = [];
    const sections = decisionsMarkdown.split(/^##\s+/m).slice(1);
    for (const rawSection of sections.slice(-6).reverse()) {
        const lines = rawSection.split(/\r?\n/);
        const rawHeading = (lines[0] ?? '').trim();
        if (!rawHeading) continue;
        const cleanTitle = rawHeading
            .replace(/\b\d{4}-\d{2}-\d{2}T[\d:.+-]+Z?\b/g, '')
            .replace(/\s+/g, ' ')
            .trim();
        const bodyLine = lines
            .slice(1)
            .map((l) => l.replace(/^[*>-]\s*/, '').trim())
            .find((l) => l.length > 12 && !l.startsWith('---') && !l.startsWith('```'));
        entries.push({
            title: cleanTitle || 'Recorded choice',
            summary: bodyLine ? bodyLine.slice(0, 220) : 'Recorded in your chosen squad decision notes.',
        });
    }
    return entries;
}

function classifyDeliverable(relativePath) {
    const ext = path.extname(relativePath).toLowerCase();
    const base = path.basename(relativePath);
    if (['.html', '.htm'].includes(ext)) {
        return { kind: 'web', friendlyType: 'Interactive Web Page' };
    }
    if (['.pptx', '.ppt'].includes(ext)) {
        return { kind: 'slides', friendlyType: 'Slide Presentation' };
    }
    if (['.docx', '.pdf'].includes(ext)) {
        return { kind: 'doc', friendlyType: 'Formatted Document' };
    }
    if (['.xlsx', '.csv'].includes(ext)) {
        return { kind: 'data', friendlyType: 'Spreadsheet / Data' };
    }
    if (/plan|roadmap|prd|brd|adr/i.test(base)) {
        return { kind: 'plan', friendlyType: 'Step-by-Step Plan' };
    }
    return { kind: 'doc', friendlyType: 'Plain-English Guide' };
}

function humanizeFileName(relativePath) {
    const stem = path.basename(relativePath, path.extname(relativePath));
    if (stem.toLowerCase() === 'index') {
        const parent = path.basename(path.dirname(relativePath));
        if (parent && parent !== '.' && parent !== 'outputs') {
            return parent.replace(/[-_]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
        }
        return 'Main Web Page';
    }
    return stem.replace(/[-_]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

/**
 * Extracts completed history milestones and deliverable paths from `.copilot-tracking/squad/history/`.
 *
 * @param {string} repoRoot
 */
async function readSquadHistory(repoRoot) {
    const historyDir = path.join(repoRoot, '.copilot-tracking', 'squad', 'history');
    const st = await statSafe(historyDir);
    if (!st || !st.isDirectory() || st.isSymbolicLink()) {
        return { completedMilestones: [], deliverableCandidates: [] };
    }

    let names = [];
    try {
        names = await fs.readdir(historyDir);
    } catch {
        return { completedMilestones: [], deliverableCandidates: [] };
    }

    const completedMilestones = [];
    const deliverableCandidates = [];

    for (const fileName of names.filter((n) => n.endsWith('.md')).slice(0, 20)) {
        const relPath = `.copilot-tracking/squad/history/${fileName}`;
        const content = await readSmallText(repoRoot, relPath);
        if (!content) continue;
        const agentName = fileName.replace(/\.md$/i, '');
        const role = describeRolePlainly(agentName);

        const sections = content.split(/^###\s+/m).slice(1);
        for (const section of sections.slice(-3)) {
            const lines = section.split(/\r?\n/);
            const heading = (lines[0] ?? '').replace(/^\S+\s+/, '').trim();
            const outcomeMatch = section.match(/^\*\s*Outcome:\s*(.+)$/im);
            const deliverableMatch = section.match(/^\*\s*Deliverable:\s*(.+)$/im);
            const outcome = outcomeMatch ? outcomeMatch[1].trim() : '';

            if (agentName !== 'Squad Scribe' && (heading || outcome)) {
                completedMilestones.push({
                    id: `hist-${agentName}-${completedMilestones.length}`,
                    status: 'done',
                    title: heading || `${role.friendlyName} completed a step`,
                    detail: outcome || role.roleSummary,
                });
            }

            if (deliverableMatch) {
                const rawDeliv = deliverableMatch[1];
                const backticked = [...rawDeliv.matchAll(/`([^`]+)`/g)].map((m) => m[1]);
                const candidates = backticked.length > 0 ? backticked : [rawDeliv.split('(')[0].trim()];
                for (const candidate of candidates) {
                    const cleaned = candidate.trim().replace(/\\/g, '/');
                    if (
                        cleaned &&
                        !cleaned.startsWith('.copilot-tracking/squad/') &&
                        !cleaned.includes('state.json') &&
                        !cleaned.endsWith('/')
                    ) {
                        deliverableCandidates.push({
                            relativePath: cleaned,
                            summary: outcome || `Created by ${role.friendlyName}`,
                        });
                    }
                }
            }
        }
    }

    return { completedMilestones, deliverableCandidates };
}

/**
 * Reads a safe plain-text preview of a deliverable file in the workspace.
 *
 * @param {string} repoRoot
 * @param {string} relativePath
 */
export async function readDeliverablePreview(repoRoot, relativePath) {
    const { fullPath, relativePath: safeRel } = await resolveSafeWorkspacePath(repoRoot, relativePath);
    const st = await statSafe(fullPath);
    if (!st || !st.isFile()) {
        throw new Error('That file could not be found in your project folder.');
    }
    const ext = path.extname(safeRel).toLowerCase();
    if (!TEXT_EXTENSIONS.has(ext)) {
        return {
            relativePath: safeRel,
            readableText: false,
            content: null,
            note: `This file (${path.basename(safeRel)}) opens best in its own app or editor.`,
        };
    }
    if (st.size > MAX_READ_BYTES) {
        return {
            relativePath: safeRel,
            readableText: false,
            content: null,
            note: 'This file is large — open it directly in your editor to view the full contents.',
        };
    }
    const content = await fs.readFile(fullPath, 'utf8');
    return {
        relativePath: safeRel,
        readableText: true,
        content,
        note: null,
    };
}

/**
 * Reads the live `.copilot-tracking/squad/` workspace state and turns it into a
 * beginner-friendly snapshot for HVE Squad Studio.
 *
 * @param {string | null | undefined} repoRoot
 */
export async function readLiveWorkspaceSnapshot(repoRoot) {
    if (!repoRoot) {
        return {
            hasSquadState: false,
            chosenSquad: {
                initialized: false,
                profileId: null,
                profileTitle: 'Selected automatically when you start',
                activePacks: [],
                turn: 0,
                spending: { estCostUsd: 0, ceilingUsd: null, remainingUsd: null },
                members: [],
            },
            intakeCheckup: null,
            councilCheckup: null,
            milestones: [],
            decisions: [],
            deliverables: [],
        };
    }

    const stateRaw = await readSmallText(repoRoot, '.copilot-tracking/squad/state.json');
    const teamRaw = await readSmallText(repoRoot, '.copilot-tracking/squad/team.md');
    const decisionsRaw = await readSmallText(repoRoot, '.copilot-tracking/squad/decisions.md');

    let parsedState = null;
    if (stateRaw) {
        try {
            parsedState = JSON.parse(stateRaw);
        } catch {
            parsedState = null;
        }
    }

    const teamInfo = parseTeamMarkdown(teamRaw);
    const decisions = parseDecisionsMarkdown(decisionsRaw);
    const { intakeCheckup, councilCheckup } = parseStructuredVerdicts(decisionsRaw);
    const { completedMilestones, deliverableCandidates } = await readSquadHistory(repoRoot);

    const activeRoles = Array.isArray(parsedState?.activeRoles) ? parsedState.activeRoles : [];
    const activeMilestones = activeRoles.map((roleName, idx) => {
        const info = describeRolePlainly(roleName);
        return {
            id: `active-${idx}-${info.friendlyName}`,
            status: 'active',
            title: info.milestoneActive,
            detail: `${info.friendlyName} — ${info.roleSummary}`,
        };
    });

    const deliverables = [];
    const seenPaths = new Set();
    for (const item of deliverableCandidates.reverse()) {
        if (seenPaths.has(item.relativePath)) continue;
        try {
            const { fullPath, relativePath } = await resolveSafeWorkspacePath(repoRoot, item.relativePath);
            const st = await statSafe(fullPath);
            if (!st || !st.isFile()) continue;
            seenPaths.add(relativePath);
            const kindInfo = classifyDeliverable(relativePath);
            let previewExcerpt = '';
            if (TEXT_EXTENSIONS.has(path.extname(relativePath).toLowerCase()) && st.size <= 32768) {
                const rawText = await fs.readFile(fullPath, 'utf8').catch(() => '');
                previewExcerpt = rawText
                    .replace(/^---[\s\S]*?---/, '')
                    .replace(/<[^>]+>/g, ' ')
                    .replace(/\s+/g, ' ')
                    .trim()
                    .slice(0, 180);
            }
            deliverables.push({
                id: `deliv-${deliverables.length + 1}`,
                kind: kindInfo.kind,
                title: humanizeFileName(relativePath),
                friendlyType: kindInfo.friendlyType,
                relativePath,
                summary: item.summary,
                previewExcerpt,
                isPreviewOnly: false,
            });
        } catch {
            // Ignore unsafe or missing paths
        }
    }

    const preflight = parsedState?.currentRun?.costPreflight ?? {};
    const estCostUsd = Number(parsedState?.currentRun?.estCostUsd ?? 0) || 0;
    const ceilingUsd = typeof preflight.ceilingUsd === 'number' ? preflight.ceilingUsd : null;
    const remainingUsd = typeof preflight.remainingUsd === 'number' ? preflight.remainingUsd : null;

    const initialized = Boolean(parsedState || teamRaw);

    return {
        hasSquadState: initialized,
        chosenSquad: {
            initialized,
            profileId: teamInfo.profileId,
            profileTitle: initialized ? teamInfo.profileTitle : 'Selected automatically when you start',
            activePacks: teamInfo.activePacks,
            turn: Number(parsedState?.turn ?? 0) || 0,
            spending: {
                estCostUsd: Math.round(estCostUsd * 100) / 100,
                ceilingUsd,
                remainingUsd: remainingUsd !== null ? Math.round(remainingUsd * 100) / 100 : null,
            },
            members: teamInfo.members,
        },
        intakeCheckup,
        councilCheckup,
        milestones: [...activeMilestones, ...completedMilestones.slice(-6)],
        decisions,
        deliverables,
    };
}
