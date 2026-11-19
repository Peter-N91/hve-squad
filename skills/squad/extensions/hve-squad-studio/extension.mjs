// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

import { CanvasError, createCanvas, joinSession } from '@github/copilot-sdk/extension';

import { GOAL_CARDS } from './lib/catalog.mjs';
import { PREVIEW_STAGES } from './lib/scenarios.mjs';
import { createStudioServer } from './lib/server.mjs';
import { createSessionBridge } from './lib/session-bridge.mjs';
import { createStudioStore } from './lib/store.mjs';

const CANVAS_ID = 'hve-squad-studio';

/** @type {import('@github/copilot-sdk/extension').CopilotSession | null} */
let joinedSession = null;

function log(message, level = 'info') {
    joinedSession?.log(`HVE Squad Studio: ${message}`, { level, ephemeral: true }).catch(() => {});
}

const instances = new Map(); // instanceId -> { server, sessionKey, url }

const store = createStudioStore({
    getSessionWorkspacePath: () => joinedSession?.workspacePath,
});

function broadcastAll() {
    for (const entry of instances.values()) {
        entry.server.broadcastUpdate().catch(() => {});
    }
}

const bridge = createSessionBridge({
    getSession: () => joinedSession,
    onStateChanged: broadcastAll,
    log,
});

function resolveSessionKey(ctx) {
    return (
        (typeof ctx?.sessionId === 'string' && ctx.sessionId) ||
        (typeof joinedSession?.sessionId === 'string' && joinedSession.sessionId) ||
        process.cwd()
    );
}

async function ensureInstance(instanceId, sessionKey) {
    let entry = instances.get(instanceId);
    if (!entry) {
        const server = await createStudioServer({
            instanceId,
            getSessionKey: () => entry?.sessionKey ?? sessionKey,
            getRepoRoot: () => process.cwd(),
            store,
            bridge,
        });
        entry = { server, sessionKey, url: server.url };
        instances.set(instanceId, entry);
    } else {
        entry.sessionKey = sessionKey;
    }
    return entry;
}

function requireOpenInstance(instanceId) {
    const entry = instances.get(instanceId);
    if (!entry) {
        throw new CanvasError('instance_not_found', `No open HVE Squad Studio instance with id "${instanceId}".`);
    }
    return entry;
}

const canvas = createCanvas({
    id: CANVAS_ID,
    displayName: 'HVE Squad Studio',
    description: 'Guided plain-language workspace for non-technical users and beginners to build websites, plans, slides, and documents with HVE Squad without writing chat commands.',
    inputSchema: {
        type: 'object',
        properties: {
            mode: {
                type: 'string',
                enum: ['live', 'preview'],
                description: 'Open connected to the live HVE Squad workspace ("live", default) or in the interactive beginner walkthrough ("preview").',
            },
            previewStage: {
                type: 'string',
                enum: [...PREVIEW_STAGES],
                description: 'When mode is "preview", selects which walkthrough screen to display first.',
            },
            activeTab: {
                type: 'string',
                enum: ['create', 'progress', 'results'],
                description: 'Initial tab to show ("create", "progress", or "results").',
            },
            goalId: {
                type: 'string',
                enum: GOAL_CARDS.map((card) => card.id),
                description: 'Optional starter goal card to pre-select.',
            },
            goalText: {
                type: 'string',
                maxLength: 2000,
                description: 'Optional plain-language goal description to pre-fill without auto-sending.',
            },
        },
        additionalProperties: false,
    },
    actions: [
        {
            name: 'get_studio_state',
            description: 'Returns the current HVE Squad Studio view state, chosen squad summary, pending questions, and deliverables.',
            inputSchema: {
                type: 'object',
                properties: {},
                additionalProperties: false,
            },
            handler: async (ctx) => {
                const entry = requireOpenInstance(ctx.instanceId);
                const state = await entry.server.assembleFullViewModel();
                return {
                    instanceId: ctx.instanceId,
                    mode: state.mode,
                    previewStage: state.previewStage,
                    activeTab: state.activeTab,
                    agentStatus: state.agentStatus,
                    chosenSquad: state.chosenSquad,
                    draft: state.draft,
                    pendingQuestion: state.pendingQuestion,
                    deliverableCount: state.deliverables.length,
                };
            },
        },
        {
            name: 'set_view',
            description: 'Switches HVE Squad Studio between live workspace mode and interactive walkthrough preview stages, or switches the active tab.',
            inputSchema: {
                type: 'object',
                properties: {
                    mode: { type: 'string', enum: ['live', 'preview'] },
                    previewStage: { type: 'string', enum: [...PREVIEW_STAGES] },
                    activeTab: { type: 'string', enum: ['create', 'progress', 'results'] },
                },
                additionalProperties: false,
            },
            handler: async (ctx) => {
                const entry = requireOpenInstance(ctx.instanceId);
                const input = ctx.input ?? {};
                const patch = {};
                if (input.mode) patch.mode = input.mode;
                if (input.previewStage) {
                    patch.previewStage = input.previewStage;
                    if (!input.mode) patch.mode = 'preview';
                }
                if (input.activeTab) patch.activeTab = input.activeTab;
                await store.saveSessionState(entry.sessionKey, patch);
                await entry.server.broadcastUpdate();
                const updated = await entry.server.assembleFullViewModel();
                return {
                    mode: updated.mode,
                    previewStage: updated.previewStage,
                    activeTab: updated.activeTab,
                };
            },
        },
        {
            name: 'prefill_goal',
            description: 'Pre-fills the HVE Squad Studio Goal Launcher with a plain-language goal and settings without submitting automatically.',
            inputSchema: {
                type: 'object',
                properties: {
                    goalId: { type: 'string', enum: GOAL_CARDS.map((card) => card.id) },
                    goalText: { type: 'string', maxLength: 2000 },
                    workingStyle: { type: 'string', enum: ['guided-auto', 'step-by-step'] },
                    budgetStyle: { type: 'string', enum: ['balanced', 'saver', 'quick'] },
                    spendingLimitUsd: { type: ['number', 'null'], minimum: 0.5, maximum: 500 },
                },
                required: ['goalText'],
                additionalProperties: false,
            },
            handler: async (ctx) => {
                const entry = requireOpenInstance(ctx.instanceId);
                const input = ctx.input ?? {};
                const saved = await store.saveSessionState(entry.sessionKey, {
                    mode: 'live',
                    activeTab: 'create',
                    draft: {
                        ...(input.goalId ? { goalId: input.goalId } : {}),
                        goalText: input.goalText,
                        ...(input.workingStyle ? { workingStyle: input.workingStyle } : {}),
                        ...(input.budgetStyle ? { budgetStyle: input.budgetStyle } : {}),
                        ...(input.spendingLimitUsd !== undefined ? { spendingLimitUsd: input.spendingLimitUsd } : {}),
                        helperOpen: false,
                    },
                });
                await entry.server.broadcastUpdate();
                return { draft: saved.draft };
            },
        },
        {
            name: 'update_preferences',
            description: 'Updates persistent HVE Squad Studio user preferences, including theme, contrast, and manual-only coexistence mode.',
            inputSchema: {
                type: 'object',
                properties: {
                    theme: { type: 'string', enum: ['system', 'light', 'dark'] },
                    contrast: { type: 'string', enum: ['standard', 'more'] },
                    neverAutoOpen: { type: 'boolean' },
                    showPlainTips: { type: 'boolean' },
                },
                additionalProperties: false,
            },
            handler: async (ctx) => {
                const entry = requireOpenInstance(ctx.instanceId);
                const preferences = await store.savePreferences(ctx.input ?? {});
                await entry.server.broadcastUpdate();
                return { preferences };
            },
        },
    ],
    open: async (ctx) => {
        const sessionKey = resolveSessionKey(ctx);
        const input = ctx.input && typeof ctx.input === 'object' ? ctx.input : {};

        if (Object.keys(input).length > 0) {
            const patch = {};
            if (input.mode) patch.mode = input.mode;
            if (input.previewStage) {
                patch.previewStage = input.previewStage;
                if (!input.mode) patch.mode = 'preview';
            }
            if (input.activeTab) patch.activeTab = input.activeTab;
            if (input.goalId !== undefined || input.goalText !== undefined) {
                patch.draft = {
                    ...(input.goalId ? { goalId: input.goalId } : {}),
                    ...(input.goalText !== undefined ? { goalText: input.goalText } : {}),
                };
            }
            await store.saveSessionState(sessionKey, patch);
        }

        const entry = await ensureInstance(ctx.instanceId, sessionKey);
        const view = await entry.server.assembleFullViewModel();
        const statusLabel = view.mode === 'preview'
            ? `HVE Squad Studio · Interactive preview (${view.previewStage})`
            : `HVE Squad Studio · ${view.agentStatus.friendlyAgent}`;

        return {
            title: 'HVE Squad Studio',
            status: statusLabel,
            url: entry.url,
        };
    },
    onClose: async (ctx) => {
        const entry = instances.get(ctx.instanceId);
        if (entry) {
            instances.delete(ctx.instanceId);
            await entry.server.close();
        }
    },
});

joinedSession = await joinSession({ canvases: [canvas] });
bridge.attachSessionListeners(joinedSession);