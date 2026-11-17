// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const EXTENSION_DIR = path.dirname(fileURLToPath(import.meta.url));

async function isRegularFile(filePath) {
    try {
        const st = await fs.lstat(filePath);
        return st.isFile() && !st.isSymbolicLink();
    } catch {
        return false;
    }
}

async function pathExists(target) {
    try {
        await fs.lstat(target);
        return true;
    } catch {
        return false;
    }
}

/**
 * Locates the installed `Get-SquadInitContext.ps1` and `Initialize-Squad.ps1` scripts
 * across plugin, APM (`.agents/skills/squad`), and repository layouts.
 *
 * @param {string} repoRoot
 */
export async function findSquadInitScripts(repoRoot) {
    const copilotHome = process.env.COPILOT_HOME?.trim()
        ? path.resolve(process.env.COPILOT_HOME.trim())
        : path.join(os.homedir(), '.copilot');

    const candidateDirs = [
        path.resolve(EXTENSION_DIR, '..', '..', '..', 'scripts'),
        path.join(repoRoot, '.agents', 'skills', 'squad', 'scripts'),
        path.join(repoRoot, '.github', 'skills', 'squad', 'scripts'),
        path.join(repoRoot, 'squad-src', '.github', 'skills', 'squad', 'scripts'),
        path.join(copilotHome, 'installed-plugins', 'hve-squad', 'hve-squad', 'skills', 'squad', 'scripts'),
    ];

    for (const dir of candidateDirs) {
        const contextScript = path.join(dir, 'Get-SquadInitContext.ps1');
        const initScript = path.join(dir, 'Initialize-Squad.ps1');
        if ((await isRegularFile(contextScript)) && (await isRegularFile(initScript))) {
            return { dir, contextScript, initScript };
        }
    }
    return null;
}

/**
 * Pre-initializes `.copilot-tracking/squad/` deterministically using HVE Squad's
 * predefined beginner defaults (single squad, matched profile, `naming: "skip"`,
 * `notify: { approvalChannel: "in-chat", enabled: false }`) when no squad exists yet
 * and no external pack preflight requires interactive skill installation first.
 *
 * @param {{
 *   repoRoot: string,
 *   profile: string,
 *   packs?: string[],
 *   modelRouting?: string,
 *   mode?: string,
 *   log?: (msg: string, level?: 'info' | 'warning' | 'error') => void
 * }} options
 */
export async function ensurePredefinedSquadInitialized(options) {
    const { repoRoot, profile, packs = [], modelRouting = 'ranked', mode = 'autopilot', log } = options;
    if (!repoRoot) {
        return { alreadyInitialized: false, preSeeded: false, reason: 'no-repo-root' };
    }

    const squadRoot = path.join(repoRoot, '.copilot-tracking', 'squad');
    const teamPath = path.join(squadRoot, 'team.md');
    const fedPath = path.join(squadRoot, 'federation.md');

    if ((await pathExists(teamPath)) || (await pathExists(fedPath))) {
        return { alreadyInitialized: true, preSeeded: false, reason: 'existing-squad' };
    }

    // When opt-in packs are requested, let Squad Coordinator run Pack Resource Preflight
    // using the predefined single-squad/naming/notify choices passed in the prompt.
    if (Array.isArray(packs) && packs.length > 0) {
        return { alreadyInitialized: false, preSeeded: false, reason: 'deferred-for-pack-preflight' };
    }

    const scripts = await findSquadInitScripts(repoRoot);
    if (!scripts) {
        return { alreadyInitialized: false, preSeeded: false, reason: 'scripts-not-found' };
    }

    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'hve-squad-studio-init-'));
    const choicesPath = path.join(tmpDir, 'choices.json');
    const payloadPath = path.join(tmpDir, 'payload.json');

    const choices = {
        confirmed: true,
        squadRoot: '.copilot-tracking/squad',
        runId: `studio-${randomUUID().slice(0, 8)}`,
        profile,
        naming: 'skip',
        notify: {
            approvalChannel: 'in-chat',
            enabled: false,
        },
        modelRouting: ['off', 'ranked', 'economy', 'manual'].includes(modelRouting) ? modelRouting : 'ranked',
        mode: ['interactive', 'autonomous', 'autopilot'].includes(mode) ? mode : 'autopilot',
        sessionModel: 'auto',
    };

    try {
        await fs.writeFile(choicesPath, `${JSON.stringify(choices, null, 2)}\n`, 'utf8');
        await execFileAsync(
            'pwsh',
            [
                '-NoProfile',
                '-File',
                scripts.contextScript,
                '-RepoRoot',
                repoRoot,
                '-ChoicesPath',
                choicesPath,
                '-PayloadPath',
                payloadPath,
            ],
            { timeout: 25000, windowsHide: true },
        );

        await execFileAsync(
            'pwsh',
            [
                '-NoProfile',
                '-File',
                scripts.initScript,
                '-RepoRoot',
                repoRoot,
                '-PayloadPath',
                payloadPath,
                '-Direct',
            ],
            { timeout: 30000, windowsHide: true },
        );

        return { alreadyInitialized: false, preSeeded: true, profile, reason: 'initialized-direct' };
    } catch (err) {
        log?.(
            `Predefined direct Init fell back to coordinator prompt (${err instanceof Error ? err.message : 'error'})`,
            'warning',
        );
        return { alreadyInitialized: false, preSeeded: false, reason: 'fallback-to-coordinator' };
    } finally {
        await fs.rm(tmpDir, { recursive: true, force: true }).catch(() => {});
    }
}
