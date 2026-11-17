// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

import path from 'node:path';

import {
    composeRefinementLaunch,
    composeStudioLaunch,
    describeRolePlainly,
    sanitizeUserText,
} from './catalog.mjs';
import { ensurePredefinedSquadInitialized } from './squad-initializer.mjs';

/**
 * Matches the HVE Squad Coordinator agent from `session.rpc.agent.list()` whether
 * installed via the `hve-squad` plugin or a repository/APM checkout.
 *
 * @param {Array<{ name?: string, displayName?: string }>} agents
 */
export function findCoordinatorAgentName(agents) {
    if (!Array.isArray(agents)) return null;
    const candidates = agents.filter((a) => a && typeof a.name === 'string');
    const exact = candidates.find((a) => {
        const n = a.name.toLowerCase();
        const d = String(a.displayName ?? '').toLowerCase();
        return (
            n === 'squad coordinator' ||
            n === 'squad-coordinator' ||
            n.endsWith(':squad-coordinator') ||
            n.endsWith('/squad-coordinator') ||
            d === 'squad coordinator'
        );
    });
    return exact ? exact.name : null;
}

/**
 * Finds the recommended option in a list of choices if one is marked `(Recommended)`
 * or falls back to the first choice when present.
 *
 * @param {string[] | undefined} choices
 */
export function pickRecommendedChoice(choices) {
    if (!Array.isArray(choices) || choices.length === 0) return null;
    const explicit = choices.find((c) => /\(recommended\)/i.test(String(c)));
    return explicit ?? choices[0];
}

/**
 * Classifies an incoming `user_input.requested` prompt so beginners see a clear
 * plain-English explanation when HVE Squad offers an opt-in council checkup,
 * pack helper installation, or uploaded-document intake question.
 *
 * @param {string} question
 * @param {string[]} choices
 */
export function classifyPendingQuestion(question, choices = []) {
    const combined = `${question} ${choices.join(' ')}`.toLowerCase();
    if (/\b(council|pre-implementation review|waive|cost-manager|rai\b.*lens|architect\b.*security)\b/.test(combined)) {
        const skipOption = choices.find((c) => /\b(skip|decline|waive|continue without)\b/i.test(c)) ?? null;
        return {
            kind: 'council',
            eyebrow: 'Extra Safety, Budget & Design Checkup Suggested',
            plainHint: 'HVE Squad noticed areas like cost, safety, or structure worth double-checking before building. Skipping records a clean waiver and will not block your project.',
            skipChoice: skipOption,
        };
    }
    if (/\b(pack|install-squadpackresources|preview skills?|core skills?|resource pack)\b/.test(combined)) {
        return {
            kind: 'pack',
            eyebrow: 'Helpful Specialist Add-On Available',
            plainHint: 'HVE Squad can add official templates and know-how for your platform. Standard helpers are recommended; experimental preview tools are optional.',
            skipChoice: choices.find((c) => /\b(continue without|skip|decline)\b/i.test(c)) ?? null,
        };
    }
    if (/\b(intake|completeness|clarity|blocking gap|uploaded|attached document)\b/.test(combined)) {
        return {
            kind: 'intake',
            eyebrow: 'Quick Question About Your Attached Document',
            plainHint: 'HVE Squad checked your attached document and needs one detail clarified so nothing is guessed.',
            skipChoice: null,
        };
    }
    return {
        kind: 'general',
        eyebrow: 'HVE Squad Needs One Quick Choice',
        plainHint: 'Answer below in one click — no special formatting needed.',
        skipChoice: null,
    };
}

/**
 * Bridges HVE Squad Studio to the live Copilot session:
 * - Auto-selects the HVE Squad Coordinator agent when starting a goal (even if no agent was selected)
 * - Switches session mode (`autopilot` or `interactive`)
 * - Sends clean `displayPrompt` + structured `prompt`
 * - Tracks live questions (`user_input.requested`), permissions (`permission.requested`), and milestones
 *
 * @param {{ getSession: () => any, onStateChanged: () => void, log: (msg: string, level?: 'info' | 'warning' | 'error') => void }} deps
 */
export function createSessionBridge(deps) {
    const liveRuntime = {
        busy: false,
        pendingQuestion: null,
        pendingPermissions: new Set(),
        liveMilestones: [],
        latestAssistantSummary: null,
        lastError: null,
    };

    function pushLiveMilestone(id, status, title, detail) {
        const existingIdx = liveRuntime.liveMilestones.findIndex((m) => m.id === id);
        const item = { id, status, title, detail, updatedAt: Date.now() };
        if (existingIdx >= 0) {
            liveRuntime.liveMilestones[existingIdx] = item;
        } else {
            liveRuntime.liveMilestones.unshift(item);
            if (liveRuntime.liveMilestones.length > 8) {
                liveRuntime.liveMilestones.length = 8;
            }
        }
    }

    function attachSessionListeners(session) {
        if (!session || typeof session.on !== 'function') return;

        session.on((event) => {
            if (!event || typeof event.type !== 'string') return;

            switch (event.type) {
                case 'assistant.turn_start': {
                    liveRuntime.busy = true;
                    liveRuntime.lastError = null;
                    deps.onStateChanged();
                    break;
                }
                case 'session.idle': {
                    liveRuntime.busy = false;
                    for (const item of liveRuntime.liveMilestones) {
                        if (item.status === 'active') item.status = 'done';
                    }
                    deps.onStateChanged();
                    break;
                }
                case 'subagent.started': {
                    const rawName = event.data?.agentDisplayName || event.data?.agentName || 'Specialist';
                    const role = describeRolePlainly(rawName);
                    pushLiveMilestone(
                        `sub-${event.agentId || rawName}`,
                        'active',
                        role.milestoneActive,
                        `${role.friendlyName} — ${sanitizeUserText(event.data?.agentDescription || role.roleSummary, 180)}`,
                    );
                    deps.onStateChanged();
                    break;
                }
                case 'subagent.completed': {
                    const rawName = event.data?.agentDisplayName || event.data?.agentName || 'Specialist';
                    const role = describeRolePlainly(rawName);
                    pushLiveMilestone(
                        `sub-${event.agentId || rawName}`,
                        'done',
                        `${role.friendlyName} finished their part`,
                        role.roleSummary,
                    );
                    deps.onStateChanged();
                    break;
                }
                case 'user_input.requested': {
                    const choices = Array.isArray(event.data?.choices) ? event.data.choices.map(String) : [];
                    const rawQ = sanitizeUserText(event.data?.question ?? 'HVE Squad has a quick question for you:', 800);
                    const meta = classifyPendingQuestion(rawQ, choices);
                    liveRuntime.pendingQuestion = {
                        requestId: String(event.data?.requestId ?? ''),
                        kind: meta.kind,
                        eyebrow: meta.eyebrow,
                        question: rawQ,
                        plainHint: meta.plainHint,
                        recommendedChoice: pickRecommendedChoice(choices),
                        skipChoice: meta.skipChoice,
                        choices,
                        allowFreeform: event.data?.allowFreeform !== false,
                    };
                    deps.onStateChanged();
                    break;
                }
                case 'user_input.completed': {
                    if (
                        liveRuntime.pendingQuestion &&
                        (!event.data?.requestId || liveRuntime.pendingQuestion.requestId === event.data.requestId)
                    ) {
                        liveRuntime.pendingQuestion = null;
                        deps.onStateChanged();
                    }
                    break;
                }
                case 'permission.requested': {
                    const id = String(event.data?.requestId ?? event.id ?? 'perm');
                    liveRuntime.pendingPermissions.add(id);
                    deps.onStateChanged();
                    break;
                }
                case 'permission.completed': {
                    const id = String(event.data?.requestId ?? '');
                    if (id) liveRuntime.pendingPermissions.delete(id);
                    else liveRuntime.pendingPermissions.clear();
                    deps.onStateChanged();
                    break;
                }
                case 'assistant.message': {
                    if (!event.agentId && typeof event.data?.content === 'string' && event.data.content.trim()) {
                        const clean = event.data.content
                            .replace(/```[\s\S]*?```/g, '')
                            .replace(/[#>*_`]+/g, ' ')
                            .replace(/\s+/g, ' ')
                            .trim();
                        if (clean) {
                            liveRuntime.latestAssistantSummary = clean.slice(0, 420);
                            deps.onStateChanged();
                        }
                    }
                    break;
                }
                case 'session.error': {
                    liveRuntime.busy = false;
                    liveRuntime.lastError = sanitizeUserText(event.data?.message ?? 'Something interrupted the turn.', 280);
                    deps.onStateChanged();
                    break;
                }
                default:
                    break;
            }
        });
    }

    async function readAgentStatus() {
        const session = deps.getSession();
        if (!session) {
            return {
                connected: false,
                selectedAgent: null,
                friendlyAgent: 'Connecting to session…',
                sessionMode: 'interactive',
                busy: false,
                note: 'Open HVE Squad Studio inside an active GitHub Copilot session to start building.',
            };
        }

        let currentName = null;
        let sessionMode = 'interactive';
        try {
            const current = await session.rpc?.agent?.getCurrent?.();
            currentName = current?.agent?.name || current?.name || null;
        } catch {
            currentName = null;
        }
        try {
            const mode = await session.rpc?.mode?.get?.();
            if (typeof mode === 'string') sessionMode = mode;
            else if (typeof mode?.mode === 'string') sessionMode = mode.mode;
        } catch {
            sessionMode = 'interactive';
        }

        const isCoordinator = currentName && /squad[- ]coordinator/i.test(currentName);
        const friendlyAgent = isCoordinator
            ? 'HVE Squad Coordinator active'
            : currentName
                ? `${describeRolePlainly(currentName).friendlyName} selected (HVE Squad Studio coordinates automatically)`
                : 'Ready — HVE Squad Studio selects HVE Squad automatically when you start';

        return {
            connected: true,
            selectedAgent: currentName,
            friendlyAgent,
            sessionMode,
            busy: liveRuntime.busy,
            note: 'You can use this visual studio with or without picking an agent first — chat remains available anytime.',
        };
    }

    async function ensureCoordinatorAndMode(desiredSessionMode) {
        const session = deps.getSession();
        if (!session) throw new Error('HVE Squad Studio is not connected to an active Copilot session.');

        let coordinatorSelected = false;
        try {
            const current = await session.rpc?.agent?.getCurrent?.();
            const currentName = current?.agent?.name || current?.name || '';
            if (/squad[- ]coordinator/i.test(currentName)) {
                coordinatorSelected = true;
            } else if (typeof session.rpc?.agent?.list === 'function' && typeof session.rpc?.agent?.select === 'function') {
                const listed = await session.rpc.agent.list({});
                const agents = Array.isArray(listed?.agents) ? listed.agents : (Array.isArray(listed) ? listed : []);
                const match = findCoordinatorAgentName(agents);
                if (match) {
                    await session.rpc.agent.select({ name: match });
                    coordinatorSelected = true;
                }
            }
        } catch (err) {
            deps.log(`Automatic agent selection fell back to skill routing: ${err instanceof Error ? err.message : 'error'}`, 'warning');
        }

        if (desiredSessionMode && typeof session.rpc?.mode?.set === 'function') {
            try {
                await session.rpc.mode.set({ mode: desiredSessionMode });
            } catch (err) {
                deps.log(`Session mode switch skipped: ${err instanceof Error ? err.message : 'error'}`, 'warning');
            }
        }

        return { session, coordinatorSelected };
    }

    async function launchGoal(payload) {
        const previewCheck = composeStudioLaunch({ ...payload, coordinatorSelected: true });
        const repoRoot = typeof payload?.repoRoot === 'string' && payload.repoRoot ? payload.repoRoot : process.cwd();

        const initOutcome = await ensurePredefinedSquadInitialized({
            repoRoot,
            profile: previewCheck.profile,
            packs: previewCheck.packs,
            modelRouting: previewCheck.routingMode,
            mode: previewCheck.sessionMode === 'autopilot' ? 'autopilot' : 'interactive',
            log: deps.log,
        });

        const { session, coordinatorSelected } = await ensureCoordinatorAndMode(previewCheck.sessionMode);
        const composed = composeStudioLaunch({
            ...payload,
            coordinatorSelected,
            preSeeded: initOutcome.preSeeded || initOutcome.alreadyInitialized,
        });

        if (typeof session.send !== 'function') {
            throw new Error('This host does not allow extensions to send messages into the conversation.');
        }

        const attachments = Array.isArray(payload?.uploadedFiles)
            ? payload.uploadedFiles
                .filter((f) => f && typeof f.relativePath === 'string' && f.relativePath.trim())
                .map((f) => ({
                    type: 'file',
                    path: path.resolve(repoRoot, f.relativePath),
                }))
            : [];

        liveRuntime.busy = true;
        liveRuntime.lastError = null;
        pushLiveMilestone(
            'launch-current',
            'active',
            attachments.length > 0
                ? 'Checking your attached document and starting HVE Squad'
                : 'Handing your goal to HVE Squad',
            composed.cleanGoal.slice(0, 180),
        );
        deps.onStateChanged();

        const sendOptions = {
            prompt: composed.prompt,
            displayPrompt: composed.displayPrompt,
            mode: 'enqueue',
        };
        if (attachments.length > 0) {
            sendOptions.attachments = attachments;
        }

        const messageId = await session.send(sendOptions);

        return {
            messageId: typeof messageId === 'string' ? messageId : null,
            displayPrompt: composed.displayPrompt,
            profile: composed.profile,
            packs: composed.packs,
            preSeeded: initOutcome.preSeeded,
            sessionMode: composed.sessionMode,
        };
    }

    async function sendRefinement(payload) {
        const composed = composeRefinementLaunch(payload);
        const { session } = await ensureCoordinatorAndMode(composed.sessionMode);
        if (typeof session.send !== 'function') {
            throw new Error('This host does not allow extensions to send messages into the conversation.');
        }

        liveRuntime.busy = true;
        pushLiveMilestone('refine-current', 'active', 'Applying your requested adjustment', composed.displayPrompt);
        deps.onStateChanged();

        const messageId = await session.send({
            prompt: composed.prompt,
            displayPrompt: composed.displayPrompt,
            mode: 'enqueue',
        });

        return {
            messageId: typeof messageId === 'string' ? messageId : null,
            displayPrompt: composed.displayPrompt,
        };
    }

    async function answerPendingQuestion({ requestId, answer, wasFreeform }) {
        const session = deps.getSession();
        if (!session) throw new Error('Not connected to an active session.');
        const cleanAnswer = sanitizeUserText(answer, 1500);
        if (!cleanAnswer) throw new Error('Please choose an option or type a short answer first.');

        if (
            liveRuntime.pendingQuestion &&
            requestId === liveRuntime.pendingQuestion.requestId &&
            typeof session.rpc?.ui?.handlePendingUserInput === 'function'
        ) {
            const res = await session.rpc.ui.handlePendingUserInput({
                requestId,
                response: {
                    answer: cleanAnswer,
                    wasFreeform: Boolean(wasFreeform),
                },
            });
            liveRuntime.pendingQuestion = null;
            deps.onStateChanged();
            return { handledViaRpc: Boolean(res?.handled ?? true) };
        }

        if (typeof session.send === 'function') {
            await session.send({
                prompt: cleanAnswer,
                displayPrompt: `HVE Squad Studio answer: ${cleanAnswer}`,
                mode: 'immediate',
            });
            liveRuntime.pendingQuestion = null;
            deps.onStateChanged();
            return { handledViaRpc: false };
        }

        throw new Error('Could not deliver your answer to the session.');
    }

    function getLiveOverlay() {
        return {
            pendingQuestion: liveRuntime.pendingQuestion,
            hostPermissionPending: liveRuntime.pendingPermissions.size > 0
                ? {
                    active: true,
                    title: 'Quick safety check waiting in the main window',
                    detail: 'For your security, GitHub Copilot needs a one-time "Allow" click in the conversation panel before HVE Squad can continue.',
                }
                : null,
            liveMilestones: [...liveRuntime.liveMilestones],
            latestSummary: liveRuntime.latestAssistantSummary,
            lastError: liveRuntime.lastError,
        };
    }

    return {
        attachSessionListeners,
        readAgentStatus,
        launchGoal,
        sendRefinement,
        answerPendingQuestion,
        getLiveOverlay,
    };
}
