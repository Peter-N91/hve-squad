// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

import { execFile } from 'node:child_process';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
    BUDGET_STYLES,
    CHOSEN_SQUAD_PROFILES,
    composeHelperBrief,
    describeProfilePlainly,
    detectSuggestedPacks,
    GOAL_CARDS,
    HELPER_STEPS,
    inferSquadProfile,
    PACK_CARDS,
    PREDEFINED_INIT_DEFAULTS,
    REFINEMENT_ACTIONS,
    SPENDING_PRESETS,
    WORKING_STYLES,
} from './catalog.mjs';
import { buildPreviewSnapshot, PREVIEW_STAGES } from './scenarios.mjs';
import {
    readDeliverablePreview,
    readLiveWorkspaceSnapshot,
    removeUploadedDocument,
    resolveSafeWorkspacePath,
    saveUploadedDocument,
} from './state-reader.mjs';

const UI_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'ui');

const STATIC_ROUTES = Object.freeze({
    '/': { file: 'index.html', type: 'text/html; charset=utf-8', template: true },
    '/index.html': { file: 'index.html', type: 'text/html; charset=utf-8', template: true },
    '/ui/styles.css': { file: 'styles.css', type: 'text/css; charset=utf-8' },
    '/ui/app.mjs': { file: 'app.mjs', type: 'text/javascript; charset=utf-8' },
});

export const CONTENT_SECURITY_POLICY = [
    "default-src 'none'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self' data:",
    "connect-src 'self'",
    "base-uri 'none'",
    "form-action 'none'",
].join('; ');

const SECURITY_HEADERS = Object.freeze({
    'Content-Security-Policy': CONTENT_SECURITY_POLICY,
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'Cache-Control': 'no-store',
});

const MAX_JSON_BYTES = 32 * 1024;
const MAX_UPLOAD_JSON_BYTES = 12 * 1024 * 1024;
const HEARTBEAT_MS = 15000;

function sendJson(res, status, payload) {
    const body = JSON.stringify(payload);
    res.writeHead(status, {
        ...SECURITY_HEADERS,
        'Content-Type': 'application/json; charset=utf-8',
    });
    res.end(body);
}

async function readJsonBody(req, maxBytes = MAX_JSON_BYTES) {
    const chunks = [];
    let total = 0;
    for await (const chunk of req) {
        total += chunk.length;
        if (total > maxBytes) {
            throw Object.assign(new Error('Request payload is too large.'), { status: 413 });
        }
        chunks.push(chunk);
    }
    if (total === 0) return {};
    try {
        return JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch {
        throw Object.assign(new Error('Invalid JSON request body.'), { status: 400 });
    }
}

function tokensMatch(expected, candidate) {
    if (typeof candidate !== 'string' || candidate.length !== expected.length) return false;
    return timingSafeEqual(Buffer.from(expected, 'utf8'), Buffer.from(candidate, 'utf8'));
}

/**
 * Opens a workspace file in VS Code when available without invoking a shell.
 *
 * @param {string} fullPath
 */
async function tryOpenInCodeEditor(fullPath) {
    const candidates = process.platform === 'win32'
        ? ['code.cmd', 'code-insiders.cmd']
        : ['code', 'code-insiders'];
    for (const cmd of candidates) {
        if (cmd.endsWith('.cmd')) continue; // Never invoke batch wrappers through a shell
        const ok = await new Promise((resolve) => {
            execFile(cmd, ['--reuse-window', fullPath], { timeout: 6000, windowsHide: true }, (err) => {
                resolve(!err);
            });
        });
        if (ok) return true;
    }
    return false;
}

/**
 * Creates a loopback-only HTTP + SSE server for one open HVE Squad Studio instance.
 *
 * @param {{
 *   instanceId: string,
 *   getSessionKey: () => string,
 *   getRepoRoot: () => string,
 *   store: ReturnType<import('./store.mjs').createStudioStore>,
 *   bridge: ReturnType<import('./session-bridge.mjs').createSessionBridge>,
 * }} deps
 */
export async function createStudioServer(deps) {
    const csrfToken = randomBytes(24).toString('hex');
    const sseClients = new Set();

    async function assembleFullViewModel() {
        const sessionKey = deps.getSessionKey();
        const [preferences, sessionState, agentStatus] = await Promise.all([
            deps.store.loadPreferences(),
            deps.store.loadSessionState(sessionKey),
            deps.bridge.readAgentStatus(),
        ]);

        const catalog = {
            goalCards: GOAL_CARDS,
            helperSteps: HELPER_STEPS,
            workingStyles: WORKING_STYLES,
            budgetStyles: BUDGET_STYLES,
            spendingPresets: SPENDING_PRESETS,
            refinementActions: REFINEMENT_ACTIONS,
            chosenSquadProfiles: CHOSEN_SQUAD_PROFILES,
            packCards: PACK_CARDS,
            predefinedInit: PREDEFINED_INIT_DEFAULTS,
            previewStages: PREVIEW_STAGES,
        };

        if (sessionState.mode === 'preview') {
            const preview = buildPreviewSnapshot(sessionState.previewStage);
            const suggestedPacks = detectSuggestedPacks(preview.draft.goalText, preview.draft.uploadedFiles);
            const resolvedProfileId = inferSquadProfile(preview.draft.goalText, preview.draft.goalId, {
                hasUploadedDocs: preview.draft.uploadedFiles.length > 0,
                validateIntake: preview.draft.validateIntake,
                profileOverride: preview.draft.profileOverride,
            });
            return {
                ...preview,
                preferences,
                catalog,
                suggestedPacks,
                resolvedInitSummary: {
                    ...PREDEFINED_INIT_DEFAULTS,
                    resolvedProfileId,
                    resolvedProfileTitle: describeProfilePlainly(resolvedProfileId),
                },
            };
        }

        const repoRoot = deps.getRepoRoot();
        const workspace = await readLiveWorkspaceSnapshot(repoRoot);
        const overlay = deps.bridge.getLiveOverlay();
        const suggestedPacks = detectSuggestedPacks(sessionState.draft.goalText, sessionState.draft.uploadedFiles);
        const resolvedProfileId = inferSquadProfile(sessionState.draft.goalText, sessionState.draft.goalId, {
            hasUploadedDocs: sessionState.draft.uploadedFiles.length > 0,
            validateIntake: sessionState.draft.validateIntake,
            profileOverride: sessionState.draft.profileOverride,
        });

        const mergedMilestones = [...overlay.liveMilestones];
        for (const item of workspace.milestones) {
            if (!mergedMilestones.some((m) => m.title === item.title)) {
                mergedMilestones.push(item);
            }
        }

        return {
            mode: 'live',
            previewStage: sessionState.previewStage,
            activeTab: overlay.pendingQuestion ? 'progress' : sessionState.activeTab,
            preferences,
            catalog,
            suggestedPacks,
            resolvedInitSummary: {
                ...PREDEFINED_INIT_DEFAULTS,
                alreadyInitialized: workspace.chosenSquad.initialized,
                resolvedProfileId: workspace.chosenSquad.initialized
                    ? (workspace.chosenSquad.profileId || resolvedProfileId)
                    : resolvedProfileId,
                resolvedProfileTitle: workspace.chosenSquad.initialized
                    ? workspace.chosenSquad.profileTitle
                    : describeProfilePlainly(resolvedProfileId),
            },
            agentStatus,
            chosenSquad: workspace.chosenSquad,
            draft: sessionState.draft,
            intakeCheckup: workspace.intakeCheckup,
            councilCheckup: workspace.councilCheckup,
            pendingQuestion: overlay.pendingQuestion,
            hostPermissionPending: overlay.hostPermissionPending,
            milestones: mergedMilestones.slice(0, 10),
            decisions: workspace.decisions,
            deliverables: workspace.deliverables,
            latestSummary: overlay.latestSummary,
            lastError: overlay.lastError,
        };
    }

    async function broadcastUpdate() {
        if (sseClients.size === 0) return;
        try {
            const state = await assembleFullViewModel();
            const payload = `event: state\ndata: ${JSON.stringify(state)}\n\n`;
            for (const client of sseClients) {
                client.write(payload);
            }
        } catch {
            // Ignore transient broadcast errors
        }
    }

    const heartbeat = setInterval(() => {
        for (const client of sseClients) {
            client.write(': keepalive\n\n');
        }
    }, HEARTBEAT_MS);
    heartbeat.unref?.();

    const server = http.createServer(async (req, res) => {
        try {
            const reqUrl = new URL(req.url ?? '/', 'http://127.0.0.1');
            const pathname = reqUrl.pathname;

            if (req.method === 'GET' && STATIC_ROUTES[pathname]) {
                const entry = STATIC_ROUTES[pathname];
                const raw = await fs.readFile(path.join(UI_DIR, entry.file), 'utf8');
                let content = raw;
                if (entry.template) {
                    const prefs = await deps.store.loadPreferences();
                    content = raw
                        .replace('__THEME__', prefs.theme)
                        .replace('__CONTRAST__', prefs.contrast)
                        .replace('__CSRF_TOKEN__', csrfToken);
                }
                res.writeHead(200, {
                    ...SECURITY_HEADERS,
                    'Content-Type': entry.type,
                });
                res.end(content);
                return;
            }

            if (req.method === 'GET' && pathname === '/api/state') {
                const state = await assembleFullViewModel();
                sendJson(res, 200, state);
                return;
            }

            if (req.method === 'GET' && pathname === '/events') {
                res.writeHead(200, {
                    ...SECURITY_HEADERS,
                    'Content-Type': 'text/event-stream; charset=utf-8',
                    Connection: 'keep-alive',
                });
                res.write(': connected\n\n');
                sseClients.add(res);
                req.on('close', () => {
                    sseClients.delete(res);
                });
                return;
            }

            if (req.method === 'POST') {
                const headerToken = req.headers['x-studio-token'];
                if (!tokensMatch(csrfToken, Array.isArray(headerToken) ? headerToken[0] : headerToken)) {
                    sendJson(res, 403, { error: 'Invalid session security token. Reload the canvas and try again.' });
                    return;
                }

                const body = await readJsonBody(
                    req,
                    pathname === '/api/upload' ? MAX_UPLOAD_JSON_BYTES : MAX_JSON_BYTES,
                );
                const sessionKey = deps.getSessionKey();

                if (pathname === '/api/upload') {
                    const current = await deps.store.loadSessionState(sessionKey);
                    if ((current.draft.uploadedFiles?.length ?? 0) >= 5) {
                        throw Object.assign(new Error('You can attach up to 5 documents per request.'), { status: 400 });
                    }
                    const savedFile = current.mode === 'preview'
                        ? {
                            relativePath: `.copilot-tracking/studio-inputs/${String(body.fileName ?? 'notes.md').replace(/[^A-Za-z0-9._-]+/g, '-')}`,
                            originalName: String(body.fileName ?? 'notes.md'),
                            sizeBytes: Math.round((String(body.base64Content ?? '').length * 3) / 4),
                            excerpt: '',
                        }
                        : await saveUploadedDocument(deps.getRepoRoot(), {
                            fileName: body.fileName,
                            base64Content: body.base64Content,
                        });

                    const existing = (current.draft.uploadedFiles ?? []).filter(
                        (f) => f.relativePath !== savedFile.relativePath,
                    );
                    await deps.store.saveSessionState(sessionKey, {
                        draft: {
                            uploadedFiles: [...existing, savedFile],
                        },
                    });
                    const state = await assembleFullViewModel();
                    sendJson(res, 200, { uploaded: savedFile, state });
                    await broadcastUpdate();
                    return;
                }

                if (pathname === '/api/upload/remove') {
                    const current = await deps.store.loadSessionState(sessionKey);
                    const targetRel = String(body.relativePath ?? '');
                    if (current.mode !== 'preview' && targetRel) {
                        await removeUploadedDocument(deps.getRepoRoot(), targetRel).catch(() => {});
                    }
                    const remaining = (current.draft.uploadedFiles ?? []).filter(
                        (f) => f.relativePath !== targetRel,
                    );
                    await deps.store.saveSessionState(sessionKey, {
                        draft: { uploadedFiles: remaining },
                    });
                    const state = await assembleFullViewModel();
                    sendJson(res, 200, { state });
                    await broadcastUpdate();
                    return;
                }

                if (pathname === '/api/draft') {
                    await deps.store.saveSessionState(sessionKey, {
                        mode: body.mode,
                        previewStage: body.previewStage,
                        activeTab: body.activeTab,
                        draft: body.draft,
                    });
                    const state = await assembleFullViewModel();
                    sendJson(res, 200, state);
                    await broadcastUpdate();
                    return;
                }

                if (pathname === '/api/helper/apply') {
                    const synthesized = composeHelperBrief(body.helperAnswers ?? {});
                    await deps.store.saveSessionState(sessionKey, {
                        mode: 'live',
                        activeTab: 'create',
                        draft: {
                            goalId: synthesized.goalId,
                            goalText: synthesized.goalText,
                            helperOpen: false,
                            helperAnswers: body.helperAnswers ?? {},
                        },
                    });
                    const state = await assembleFullViewModel();
                    sendJson(res, 200, { synthesized, state });
                    await broadcastUpdate();
                    return;
                }

                if (pathname === '/api/preferences') {
                    const preferences = await deps.store.savePreferences(body);
                    sendJson(res, 200, { preferences });
                    await broadcastUpdate();
                    return;
                }

                if (pathname === '/api/launch') {
                    const current = await deps.store.loadSessionState(sessionKey);
                    const saved = await deps.store.saveSessionState(sessionKey, {
                        mode: 'live',
                        activeTab: 'progress',
                        draft: {
                            goalId: body.goalId ?? current.draft.goalId,
                            goalText: body.goalText ?? current.draft.goalText,
                            workingStyle: body.workingStyle ?? current.draft.workingStyle,
                            budgetStyle: body.budgetStyle ?? current.draft.budgetStyle,
                            spendingLimitUsd: body.spendingLimitUsd !== undefined ? body.spendingLimitUsd : current.draft.spendingLimitUsd,
                            profileOverride: body.profileOverride ?? current.draft.profileOverride,
                            selectedPacks: body.selectedPacks ?? current.draft.selectedPacks,
                            allowPackPreviews: body.allowPackPreviews !== undefined ? body.allowPackPreviews : current.draft.allowPackPreviews,
                            requestCouncilCheckup: body.requestCouncilCheckup !== undefined ? body.requestCouncilCheckup : current.draft.requestCouncilCheckup,
                            validateIntake: body.validateIntake !== undefined ? body.validateIntake : current.draft.validateIntake,
                            helperOpen: false,
                        },
                    });
                    const launched = await deps.bridge.launchGoal({
                        repoRoot: deps.getRepoRoot(),
                        goalId: saved.draft.goalId,
                        goalText: saved.draft.goalText,
                        workingStyle: saved.draft.workingStyle,
                        budgetStyle: saved.draft.budgetStyle,
                        spendingLimitUsd: saved.draft.spendingLimitUsd,
                        profileOverride: saved.draft.profileOverride,
                        selectedPacks: saved.draft.selectedPacks,
                        allowPackPreviews: saved.draft.allowPackPreviews,
                        requestCouncilCheckup: saved.draft.requestCouncilCheckup,
                        validateIntake: saved.draft.validateIntake,
                        uploadedFiles: saved.draft.uploadedFiles,
                    });
                    const state = await assembleFullViewModel();
                    sendJson(res, 200, { launched, state });
                    await broadcastUpdate();
                    return;
                }

                if (pathname === '/api/refine') {
                    await deps.store.saveSessionState(sessionKey, {
                        mode: 'live',
                        activeTab: 'progress',
                    });
                    const current = await deps.store.loadSessionState(sessionKey);
                    const refined = await deps.bridge.sendRefinement({
                        refinementId: body.refinementId,
                        details: body.details,
                        deliverablePath: body.deliverablePath,
                        workingStyle: current.draft.workingStyle,
                    });
                    const state = await assembleFullViewModel();
                    sendJson(res, 200, { refined, state });
                    await broadcastUpdate();
                    return;
                }

                if (pathname === '/api/question/answer') {
                    const current = await deps.store.loadSessionState(sessionKey);
                    if (current.mode === 'preview') {
                        await deps.store.saveSessionState(sessionKey, {
                            mode: 'preview',
                            previewStage: 'working',
                            activeTab: 'progress',
                        });
                        const state = await assembleFullViewModel();
                        sendJson(res, 200, { answered: true, previewAdvanced: true, state });
                        await broadcastUpdate();
                        return;
                    }

                    const result = await deps.bridge.answerPendingQuestion({
                        requestId: body.requestId,
                        answer: body.answer,
                        wasFreeform: Boolean(body.wasFreeform),
                    });
                    const state = await assembleFullViewModel();
                    sendJson(res, 200, { answered: true, ...result, state });
                    await broadcastUpdate();
                    return;
                }

                if (pathname === '/api/deliverable/preview') {
                    const current = await deps.store.loadSessionState(sessionKey);
                    if (current.mode === 'preview') {
                        const snap = buildPreviewSnapshot('results');
                        const item = snap.deliverables.find((d) => d.relativePath === body.relativePath) ?? snap.deliverables[0];
                        sendJson(res, 200, {
                            relativePath: item.relativePath,
                            readableText: true,
                            content: `# ${item.title}\n\n${item.summary}\n\n${item.previewExcerpt}`,
                            note: 'Sample walkthrough deliverable preview.',
                        });
                        return;
                    }
                    const preview = await readDeliverablePreview(deps.getRepoRoot(), String(body.relativePath ?? ''));
                    sendJson(res, 200, preview);
                    return;
                }

                if (pathname === '/api/deliverable/open') {
                    const { fullPath, relativePath } = await resolveSafeWorkspacePath(
                        deps.getRepoRoot(),
                        String(body.relativePath ?? ''),
                    );
                    const openedInEditor = await tryOpenInCodeEditor(fullPath);
                    sendJson(res, 200, {
                        relativePath,
                        openedInEditor,
                        message: openedInEditor
                            ? `Opened ${relativePath} in VS Code.`
                            : `File is saved at ${relativePath} in your project folder.`,
                    });
                    return;
                }
            }

            sendJson(res, 404, { error: 'Route not found.' });
        } catch (err) {
            const status = typeof err?.status === 'number' ? err.status : 400;
            sendJson(res, status, {
                error: err instanceof Error ? err.message : 'Unexpected server error.',
            });
        }
    });

    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    const port = typeof address === 'object' && address ? address.port : 0;

    return {
        url: `http://127.0.0.1:${port}/`,
        assembleFullViewModel,
        broadcastUpdate,
        async close() {
            clearInterval(heartbeat);
            for (const client of sseClients) {
                client.end();
            }
            sseClients.clear();
            await new Promise((resolve) => server.close(() => resolve()));
        },
    };
}