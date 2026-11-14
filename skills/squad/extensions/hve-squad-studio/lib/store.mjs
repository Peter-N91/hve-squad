// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { CHOSEN_SQUAD_PROFILES, PACK_CARDS, sanitizeUserText } from './catalog.mjs';
import { PREVIEW_STAGES } from './scenarios.mjs';

const DEFAULT_PREFERENCES = Object.freeze({
    theme: 'system',
    contrast: 'standard',
    neverAutoOpen: false,
    showPlainTips: true,
});

const DEFAULT_SESSION_STATE = Object.freeze({
    mode: 'live',
    previewStage: 'start',
    activeTab: 'create',
    draft: {
        goalId: 'web-app',
        goalText: '',
        workingStyle: 'guided-auto',
        budgetStyle: 'balanced',
        spendingLimitUsd: null,
        profileOverride: 'auto',
        selectedPacks: [],
        allowPackPreviews: false,
        packsDrawerOpen: false,
        requestCouncilCheckup: false,
        validateIntake: true,
        uploadedFiles: [],
        helperOpen: false,
        helperAnswers: {
            outcomeId: 'interactive-app',
            audienceId: 'customers-public',
            readinessId: 'just-an-idea',
            topicNote: '',
        },
    },
});

function resolveCopilotHome() {
    const envHome = process.env.COPILOT_HOME;
    if (typeof envHome === 'string' && envHome.trim()) {
        return path.resolve(envHome.trim());
    }
    return path.join(os.homedir(), '.copilot');
}

function safeKey(raw) {
    const cleaned = String(raw ?? 'default').replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 96);
    return cleaned || 'default';
}

async function readJsonSafe(filePath) {
    try {
        const text = await fs.readFile(filePath, 'utf8');
        return JSON.parse(text);
    } catch {
        return null;
    }
}

async function writeJsonAtomic(filePath, data) {
    const dir = path.dirname(filePath);
    await fs.mkdir(dir, { recursive: true });
    const tempPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
    await fs.writeFile(tempPath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
    await fs.rename(tempPath, filePath);
}

/**
 * Validates and normalizes a preferences patch.
 *
 * @param {Record<string, unknown>} current
 * @param {Record<string, unknown>} patch
 */
export function normalizePreferences(current = {}, patch = {}) {
    const base = { ...DEFAULT_PREFERENCES, ...current };
    const next = { ...base };
    if (patch && typeof patch === 'object') {
        if (['system', 'light', 'dark'].includes(String(patch.theme))) {
            next.theme = String(patch.theme);
        }
        if (['standard', 'more'].includes(String(patch.contrast))) {
            next.contrast = String(patch.contrast);
        }
        if (typeof patch.neverAutoOpen === 'boolean') {
            next.neverAutoOpen = patch.neverAutoOpen;
        }
        if (typeof patch.showPlainTips === 'boolean') {
            next.showPlainTips = patch.showPlainTips;
        }
    }
    return next;
}

/**
 * Validates and normalizes durable session studio state.
 *
 * @param {Record<string, unknown>} current
 * @param {Record<string, unknown>} patch
 */
export function normalizeSessionStudioState(current = {}, patch = {}) {
    const mergedDraft = {
        ...DEFAULT_SESSION_STATE.draft,
        ...(current?.draft && typeof current.draft === 'object' ? current.draft : {}),
        ...(patch?.draft && typeof patch.draft === 'object' ? patch.draft : {}),
    };
    const mergedHelper = {
        ...DEFAULT_SESSION_STATE.draft.helperAnswers,
        ...(current?.draft?.helperAnswers && typeof current.draft.helperAnswers === 'object' ? current.draft.helperAnswers : {}),
        ...(patch?.draft?.helperAnswers && typeof patch.draft.helperAnswers === 'object' ? patch.draft.helperAnswers : {}),
    };

    let spendingLimitUsd = mergedDraft.spendingLimitUsd;
    if (spendingLimitUsd !== null && spendingLimitUsd !== undefined && spendingLimitUsd !== '') {
        const num = Number(spendingLimitUsd);
        spendingLimitUsd = Number.isFinite(num) && num > 0 && num <= 500 ? Math.round(num * 100) / 100 : null;
    } else {
        spendingLimitUsd = null;
    }

    const modeCandidate = patch?.mode ?? current?.mode ?? DEFAULT_SESSION_STATE.mode;
    const previewCandidate = patch?.previewStage ?? current?.previewStage ?? DEFAULT_SESSION_STATE.previewStage;
    const tabCandidate = patch?.activeTab ?? current?.activeTab ?? DEFAULT_SESSION_STATE.activeTab;

    const validPackIds = new Set(PACK_CARDS.map((p) => p.id));
    const selectedPacks = Array.isArray(mergedDraft.selectedPacks)
        ? [...new Set(mergedDraft.selectedPacks.map((p) => String(p).trim().toLowerCase()).filter((p) => validPackIds.has(p)))]
        : [];

    const validProfileIds = new Set(CHOSEN_SQUAD_PROFILES.map((p) => p.id));
    const profileOverride = validProfileIds.has(String(mergedDraft.profileOverride ?? 'auto').toLowerCase())
        ? String(mergedDraft.profileOverride ?? 'auto').toLowerCase()
        : 'auto';

    const uploadedFiles = Array.isArray(mergedDraft.uploadedFiles)
        ? mergedDraft.uploadedFiles
            .filter((f) => f && typeof f.relativePath === 'string' && f.relativePath.trim())
            .slice(0, 5)
            .map((f) => ({
                relativePath: sanitizeUserText(f.relativePath, 260),
                originalName: sanitizeUserText(f.originalName || f.relativePath, 140),
                sizeBytes: Number(f.sizeBytes) > 0 ? Math.round(Number(f.sizeBytes)) : 0,
                excerpt: sanitizeUserText(f.excerpt ?? '', 400),
            }))
        : [];

    return {
        mode: modeCandidate === 'preview' ? 'preview' : 'live',
        previewStage: PREVIEW_STAGES.includes(String(previewCandidate)) ? String(previewCandidate) : 'start',
        activeTab: ['create', 'progress', 'results'].includes(String(tabCandidate)) ? String(tabCandidate) : 'create',
        draft: {
            goalId: sanitizeUserText(mergedDraft.goalId ?? 'web-app', 64) || 'web-app',
            goalText: sanitizeUserText(mergedDraft.goalText ?? '', 2000),
            workingStyle: ['guided-auto', 'step-by-step'].includes(String(mergedDraft.workingStyle))
                ? String(mergedDraft.workingStyle)
                : 'guided-auto',
            budgetStyle: ['balanced', 'saver', 'quick'].includes(String(mergedDraft.budgetStyle))
                ? String(mergedDraft.budgetStyle)
                : 'balanced',
            spendingLimitUsd,
            profileOverride,
            selectedPacks,
            allowPackPreviews: Boolean(mergedDraft.allowPackPreviews),
            packsDrawerOpen: Boolean(mergedDraft.packsDrawerOpen),
            requestCouncilCheckup: Boolean(mergedDraft.requestCouncilCheckup),
            validateIntake: mergedDraft.validateIntake !== false,
            uploadedFiles,
            helperOpen: Boolean(mergedDraft.helperOpen),
            helperAnswers: {
                outcomeId: sanitizeUserText(mergedHelper.outcomeId ?? 'interactive-app', 64),
                audienceId: sanitizeUserText(mergedHelper.audienceId ?? 'customers-public', 64),
                readinessId: sanitizeUserText(mergedHelper.readinessId ?? 'just-an-idea', 64),
                topicNote: sanitizeUserText(mergedHelper.topicNote ?? '', 500),
            },
        },
    };
}

/**
 * Creates durable global preference and per-session state storage.
 * Never keys durable state by transient canvas `instanceId`.
 *
 * @param {{ artifactsDir?: string, getSessionWorkspacePath?: () => string | undefined }} [options]
 */
export function createStudioStore(options = {}) {
    const globalRoot = options.artifactsDir
        ? path.resolve(options.artifactsDir)
        : path.join(resolveCopilotHome(), 'extensions', 'hve-squad-studio', 'artifacts');
    const preferencesPath = path.join(globalRoot, 'preferences.json');

    function resolveSessionStatePath(sessionKey) {
        const wsPath = options.getSessionWorkspacePath?.();
        if (typeof wsPath === 'string' && wsPath.trim()) {
            return path.join(wsPath, 'files', 'hve-squad-studio-state.json');
        }
        return path.join(globalRoot, 'sessions', `${safeKey(sessionKey)}.json`);
    }

    return {
        globalRoot,
        async loadPreferences() {
            const raw = await readJsonSafe(preferencesPath);
            return normalizePreferences(DEFAULT_PREFERENCES, raw ?? {});
        },
        async savePreferences(patch) {
            const current = await this.loadPreferences();
            const next = normalizePreferences(current, patch);
            await writeJsonAtomic(preferencesPath, next);
            return next;
        },
        async loadSessionState(sessionKey) {
            const filePath = resolveSessionStatePath(sessionKey);
            const raw = await readJsonSafe(filePath);
            return normalizeSessionStudioState(DEFAULT_SESSION_STATE, raw ?? {});
        },
        async saveSessionState(sessionKey, patch) {
            const filePath = resolveSessionStatePath(sessionKey);
            const current = await this.loadSessionState(sessionKey);
            const next = normalizeSessionStudioState(current, patch);
            await writeJsonAtomic(filePath, next);
            return next;
        },
    };
}