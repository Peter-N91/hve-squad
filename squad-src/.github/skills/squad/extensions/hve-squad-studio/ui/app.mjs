// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

const csrfToken = document.documentElement.dataset.csrfToken || '';

const STAGE_LABELS = {
    start: '1. Goal & Setup',
    'intake-addons': '2. Upload & Add-Ons',
    helper: '3. 3-Click Helper',
    decision: '4. Checkup & Choice',
    working: '5. Live Progress',
    results: '6. Finished Results',
};

let appState = null;
let selectedRefinementId = 'visual-polish';
let selectedDeliverablePath = null;
let draftSyncTimer = null;
let profilePickerOpen = false;

function formatBytes(bytes) {
    const n = Number(bytes) || 0;
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${Math.max(1, Math.round(n / 1024))} KB`;
    return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function fileToBase64(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const raw = String(reader.result ?? '');
            const idx = raw.indexOf(',');
            resolve(idx >= 0 ? raw.slice(idx + 1) : raw);
        };
        reader.onerror = () => reject(new Error('Could not read that file.'));
        reader.readAsDataURL(file);
    });
}

function $(id) {
    return document.getElementById(id);
}

function svgIcon(name, extraClass = '') {
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('class', `icon ${extraClass}`.trim());
    svg.setAttribute('aria-hidden', 'true');
    const use = document.createElementNS(ns, 'use');
    use.setAttribute('href', `#i-${name}`);
    svg.appendChild(use);
    return svg;
}

function announce(text) {
    const el = $('srAnnouncer');
    if (el) el.textContent = text;
}

function showToast(message) {
    const banner = $('toastBanner');
    if (!banner) return;
    banner.textContent = message;
    banner.hidden = false;
    announce(message);
    setTimeout(() => {
        if (banner.textContent === message) banner.hidden = true;
    }, 5000);
}

async function apiPost(route, payload = {}) {
    const res = await fetch(route, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-Studio-Token': csrfToken,
        },
        body: JSON.stringify(payload),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
        throw new Error(data.error || 'Could not complete that action.');
    }
    return data;
}

function applyAppearance(preferences) {
    if (!preferences) return;
    document.documentElement.dataset.studioTheme = preferences.theme || 'system';
    document.documentElement.dataset.studioContrast = preferences.contrast || 'standard';

    for (const radio of document.querySelectorAll('input[name="studioTheme"]')) {
        radio.checked = radio.value === (preferences.theme || 'system');
    }
    $('contrastToggle').checked = preferences.contrast === 'more';
    $('plainTipsToggle').checked = preferences.showPlainTips !== false;
    $('neverAutoOpenToggle').checked = Boolean(preferences.neverAutoOpen);

    const tipEl = $('composerTip');
    if (tipEl) tipEl.hidden = preferences.showPlainTips === false;
}

function renderHeader(state) {
    $('agentStatusLine').textContent = state.agentStatus?.friendlyAgent || 'Ready with HVE Squad';

    const isPreview = state.mode === 'preview';
    const toggleBtn = $('modeToggleBtn');
    toggleBtn.setAttribute('aria-pressed', String(isPreview));
    $('modeToggleLabel').textContent = isPreview ? 'Viewing Walkthrough' : 'See Walkthrough';

    const bar = $('walkthroughBar');
    bar.hidden = !isPreview;
    if (isPreview) {
        const container = $('walkthroughSteps');
        container.replaceChildren();
        for (const stage of state.catalog.previewStages) {
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'stage-chip';
            btn.textContent = STAGE_LABELS[stage] || stage;
            btn.setAttribute('aria-pressed', String(state.previewStage === stage));
            btn.addEventListener('click', async () => {
                const next = await apiPost('/api/draft', { mode: 'preview', previewStage: stage });
                renderAll(next);
            });
            container.appendChild(btn);
        }
    }

    for (const tabId of ['create', 'progress', 'results']) {
        const active = state.activeTab === tabId;
        $(`tab-${tabId}`).setAttribute('aria-selected', String(active));
        $(`panel-${tabId}`).hidden = !active;
    }

    const needsAttention = Boolean(state.pendingQuestion || state.hostPermissionPending?.active);
    $('progressBadge').hidden = !needsAttention;

    const delivCount = state.deliverables?.length || 0;
    const resultsBadge = $('resultsBadge');
    resultsBadge.hidden = delivCount === 0;
    resultsBadge.textContent = String(delivCount);
}

function renderCreateTab(state) {
    const { catalog, draft } = state;
    const helperOpen = Boolean(draft.helperOpen);
    $('helperDrawer').hidden = !helperOpen;
    $('toggleHelperBtn').setAttribute('aria-expanded', String(helperOpen));
    $('toggleHelperLabel').textContent = helperOpen ? 'Hide 3-click helper' : 'Not sure where to start?';

    // Helper steps
    const stepsContainer = $('helperStepsContainer');
    stepsContainer.replaceChildren();
    for (const step of catalog.helperSteps) {
        const box = document.createElement('div');
        box.className = 'helper-step-box';
        const h4 = document.createElement('h4');
        h4.className = 'helper-step-title';
        h4.textContent = `Step ${step.stepNumber}: ${step.question}`;
        const hint = document.createElement('p');
        hint.className = 'muted';
        hint.textContent = step.hint;
        const choicesWrap = document.createElement('div');
        choicesWrap.className = 'helper-choices';

        const answerKey = `${step.id}Id`;
        const currentVal = draft.helperAnswers?.[answerKey];

        for (const choice of step.choices) {
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'helper-choice-btn';
            btn.setAttribute('aria-pressed', String(currentVal === choice.id));
            const titleSpan = document.createElement('span');
            titleSpan.className = 'helper-choice-title';
            titleSpan.textContent = choice.label;
            const detailSpan = document.createElement('span');
            detailSpan.className = 'helper-choice-detail';
            detailSpan.textContent = choice.detail;
            btn.append(titleSpan, detailSpan);
            btn.addEventListener('click', async () => {
                const updated = await apiPost('/api/draft', {
                    draft: {
                        helperOpen: true,
                        helperAnswers: { [answerKey]: choice.id },
                    },
                });
                renderAll(updated);
            });
            choicesWrap.appendChild(btn);
        }

        box.append(h4, hint, choicesWrap);
        stepsContainer.appendChild(box);
    }

    const topicInput = $('helperTopicInput');
    if (document.activeElement !== topicInput) {
        topicInput.value = draft.helperAnswers?.topicNote || '';
    }

    // Starter goal cards
    const grid = $('goalCardsGrid');
    grid.replaceChildren();
    const activeCard = catalog.goalCards.find((c) => c.id === draft.goalId) || catalog.goalCards[0];

    for (const card of catalog.goalCards) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'goal-card';
        btn.setAttribute('role', 'radio');
        btn.setAttribute('aria-checked', String(card.id === draft.goalId));

        const top = document.createElement('div');
        top.className = 'goal-card-top';
        const iconWrap = document.createElement('span');
        iconWrap.className = 'goal-icon';
        iconWrap.appendChild(svgIcon(card.icon));
        const badge = document.createElement('span');
        badge.className = 'goal-badge';
        badge.textContent = card.badge;
        top.append(iconWrap, badge);

        const title = document.createElement('span');
        title.className = 'goal-card-title';
        title.textContent = card.title;

        const summary = document.createElement('span');
        summary.className = 'goal-card-summary';
        summary.textContent = card.summary;

        btn.append(top, title, summary);
        btn.addEventListener('click', async () => {
            const updated = await apiPost('/api/draft', {
                draft: { goalId: card.id },
            });
            renderAll(updated);
        });
        grid.appendChild(btn);
    }

    const textarea = $('goalTextarea');
    textarea.placeholder = activeCard.placeholder;
    if (document.activeElement !== textarea) {
        textarea.value = draft.goalText || '';
    }

    // Uploaded files & Intake Checkup toggle
    const files = Array.isArray(draft.uploadedFiles) ? draft.uploadedFiles : [];
    const pillList = $('uploadedFilesList');
    pillList.replaceChildren();
    pillList.hidden = files.length === 0;
    for (const f of files) {
        const pill = document.createElement('span');
        pill.className = 'file-pill';
        pill.appendChild(svgIcon('document'));
        pill.appendChild(document.createTextNode(`${f.originalName || f.relativePath} (${formatBytes(f.sizeBytes)})`));
        const rmBtn = document.createElement('button');
        rmBtn.type = 'button';
        rmBtn.className = 'file-pill-remove';
        rmBtn.setAttribute('aria-label', `Remove ${f.originalName || f.relativePath}`);
        rmBtn.appendChild(svgIcon('x'));
        rmBtn.addEventListener('click', async () => {
            const res = await apiPost('/api/upload/remove', { relativePath: f.relativePath });
            renderAll(res.state);
        });
        pill.appendChild(rmBtn);
        pillList.appendChild(pill);
    }

    const intakeRow = $('intakeToggleRow');
    intakeRow.hidden = files.length === 0;
    intakeRow.classList.toggle('is-selected', draft.validateIntake !== false);
    $('validateIntakeCheckbox').checked = draft.validateIntake !== false;

    // Auto-detected & selected Platform Specialist Add-Ons (Packs)
    const selectedPacks = new Set(Array.isArray(draft.selectedPacks) ? draft.selectedPacks : []);
    const suggested = Array.isArray(state.suggestedPacks) ? state.suggestedPacks : [];
    const visiblePackCards = [];
    const seenPackIds = new Set();

    for (const s of suggested) {
        seenPackIds.add(s.id);
        visiblePackCards.push(s);
    }
    for (const p of catalog.packCards || []) {
        if (selectedPacks.has(p.id) && !seenPackIds.has(p.id)) {
            seenPackIds.add(p.id);
            visiblePackCards.push({ ...p, matchedTerm: null });
        }
    }

    const suggestedCard = $('suggestedPacksCard');
    const suggestedList = $('suggestedPacksList');
    suggestedList.replaceChildren();
    if (visiblePackCards.length > 0) {
        suggestedCard.hidden = false;
        for (const pack of visiblePackCards) {
            const isOn = selectedPacks.has(pack.id);
            const row = document.createElement('div');
            row.className = `pack-row ${isOn ? 'is-selected' : ''}`.trim();
            const copy = document.createElement('div');
            const title = document.createElement('div');
            title.className = 'radio-card-title';
            title.textContent = pack.matchedTerm
                ? `${pack.title} (noticed "${pack.matchedTerm}")`
                : pack.title;
            const why = document.createElement('div');
            why.className = 'radio-card-desc';
            why.textContent = pack.plainWhy;
            copy.append(title, why);

            const toggleBtn = document.createElement('button');
            toggleBtn.type = 'button';
            toggleBtn.className = isOn ? 'primary-btn' : 'secondary-btn';
            toggleBtn.textContent = isOn ? 'Included ✓' : 'Include Specialists';
            toggleBtn.addEventListener('click', async () => {
                const nextSet = new Set(selectedPacks);
                if (isOn) nextSet.delete(pack.id);
                else nextSet.add(pack.id);
                const updated = await apiPost('/api/draft', {
                    draft: { selectedPacks: [...nextSet] },
                });
                renderAll(updated);
            });
            row.append(copy, toggleBtn);
            suggestedList.appendChild(row);
        }

        const selectedWithPreview = (catalog.packCards || []).filter(
            (p) => selectedPacks.has(p.id) && p.hasPreview,
        );
        const previewRow = $('packPreviewToggleRow');
        if (selectedWithPreview.length > 0) {
            previewRow.hidden = false;
            previewRow.classList.toggle('is-selected', Boolean(draft.allowPackPreviews));
            $('allowPackPreviewsCheckbox').checked = Boolean(draft.allowPackPreviews);
            $('packPreviewDesc').textContent = selectedWithPreview[0].previewNote
                || 'Off by default — official stable helpers are already included automatically.';
        } else {
            previewRow.hidden = true;
        }
    } else {
        suggestedCard.hidden = true;
    }

    // Optional manual platform add-ons drawer
    const drawerOpen = Boolean(draft.packsDrawerOpen);
    $('allPacksDrawer').hidden = !drawerOpen;
    $('togglePacksDrawerBtn').setAttribute('aria-expanded', String(drawerOpen));
    const allPacksGrid = $('allPacksGrid');
    allPacksGrid.replaceChildren();
    if (drawerOpen) {
        for (const pack of catalog.packCards || []) {
            const isOn = selectedPacks.has(pack.id);
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'goal-card';
            btn.setAttribute('aria-checked', String(isOn));
            const t = document.createElement('span');
            t.className = 'goal-card-title';
            t.textContent = isOn ? `${pack.title} ✓` : pack.title;
            const d = document.createElement('span');
            d.className = 'goal-card-summary';
            d.textContent = pack.plainWhy;
            btn.append(t, d);
            btn.addEventListener('click', async () => {
                const nextSet = new Set(selectedPacks);
                if (isOn) nextSet.delete(pack.id);
                else nextSet.add(pack.id);
                const updated = await apiPost('/api/draft', {
                    draft: { selectedPacks: [...nextSet] },
                });
                renderAll(updated);
            });
            allPacksGrid.appendChild(btn);
        }
    }

    // Working style radio stack
    const wsList = $('workingStyleList');
    wsList.replaceChildren();
    for (const ws of catalog.workingStyles) {
        const label = document.createElement('label');
        label.className = `radio-card ${draft.workingStyle === ws.id ? 'is-selected' : ''}`.trim();
        const input = document.createElement('input');
        input.type = 'radio';
        input.name = 'workingStyle';
        input.value = ws.id;
        input.checked = draft.workingStyle === ws.id;
        input.addEventListener('change', async () => {
            const updated = await apiPost('/api/draft', { draft: { workingStyle: ws.id } });
            renderAll(updated);
        });
        const copy = document.createElement('div');
        const t = document.createElement('span');
        t.className = 'radio-card-title';
        t.textContent = ws.label;
        const d = document.createElement('span');
        d.className = 'radio-card-desc';
        d.textContent = ws.description;
        copy.append(t, d);
        label.append(input, copy);
        wsList.appendChild(label);
    }

    const councilRow = $('councilCheckupRow');
    councilRow.classList.toggle('is-selected', Boolean(draft.requestCouncilCheckup));
    $('councilCheckupCheckbox').checked = Boolean(draft.requestCouncilCheckup);

    // Predefined Initialization Strip
    const initSummary = state.resolvedInitSummary || {};
    const matchedTitle = initSummary.resolvedProfileTitle || 'Product & Experience Squad';
    const profileModeNote = draft.profileOverride && draft.profileOverride !== 'auto'
        ? `${matchedTitle} (chosen by you)`
        : `${matchedTitle} (matched automatically)`;
    $('predefinedSummaryText').textContent = `Single chosen squad · ${profileModeNote} · Updates right here in HVE Squad Studio & chat`;

    $('profileOverrideRow').hidden = !profilePickerOpen;
    $('toggleProfileSelectBtn').setAttribute('aria-expanded', String(profilePickerOpen));
    const selectEl = $('profileOverrideSelect');
    selectEl.replaceChildren();
    for (const prof of catalog.chosenSquadProfiles || []) {
        const opt = document.createElement('option');
        opt.value = prof.id;
        opt.textContent = `${prof.title} — ${prof.summary}`;
        opt.selected = (draft.profileOverride || 'auto') === prof.id;
        selectEl.appendChild(opt);
    }

    // Budget style radio stack
    const bsList = $('budgetStyleList');
    bsList.replaceChildren();
    for (const bs of catalog.budgetStyles) {
        const label = document.createElement('label');
        label.className = `radio-card ${draft.budgetStyle === bs.id ? 'is-selected' : ''}`.trim();
        const input = document.createElement('input');
        input.type = 'radio';
        input.name = 'budgetStyle';
        input.value = bs.id;
        input.checked = draft.budgetStyle === bs.id;
        input.addEventListener('change', async () => {
            const updated = await apiPost('/api/draft', { draft: { budgetStyle: bs.id } });
            renderAll(updated);
        });
        const copy = document.createElement('div');
        const t = document.createElement('span');
        t.className = 'radio-card-title';
        t.textContent = bs.label;
        const d = document.createElement('span');
        d.className = 'radio-card-desc';
        d.textContent = bs.description;
        copy.append(t, d);
        label.append(input, copy);
        bsList.appendChild(label);
    }

    // Spending presets
    const spList = $('spendingPresetList');
    spList.replaceChildren();
    for (const sp of catalog.spendingPresets) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'preset-pill';
        btn.setAttribute('role', 'radio');
        const selected = (draft.spendingLimitUsd ?? null) === sp.usd;
        btn.setAttribute('aria-checked', String(selected));
        btn.textContent = sp.label;
        btn.addEventListener('click', async () => {
            const updated = await apiPost('/api/draft', { draft: { spendingLimitUsd: sp.usd } });
            renderAll(updated);
        });
        spList.appendChild(btn);
    }
}

function renderProgressTab(state) {
    // Permission cue
    const permBanner = $('permissionBanner');
    permBanner.replaceChildren();
    if (state.hostPermissionPending?.active) {
        permBanner.hidden = false;
        const t = document.createElement('p');
        t.className = 'callout-title';
        t.textContent = state.hostPermissionPending.title;
        const d = document.createElement('p');
        d.className = 'callout-detail';
        d.textContent = state.hostPermissionPending.detail;
        permBanner.append(t, d);
    } else {
        permBanner.hidden = true;
    }

    // Error banner
    const errBanner = $('errorBanner');
    errBanner.replaceChildren();
    if (state.lastError) {
        errBanner.hidden = false;
        const t = document.createElement('p');
        t.className = 'callout-title';
        t.textContent = 'Something interrupted that step';
        const d = document.createElement('p');
        d.className = 'callout-detail';
        d.textContent = state.lastError;
        errBanner.append(t, d);
    } else {
        errBanner.hidden = true;
    }

    // Intake Checkup Verdict Card
    const intakeWrap = $('intakeCheckupContainer');
    intakeWrap.replaceChildren();
    if (state.intakeCheckup) {
        intakeWrap.hidden = false;
        const ic = state.intakeCheckup;
        const box = document.createElement('section');
        box.className = 'checkup-card';
        box.dataset.state = ic.verdict === 'Not-Ready' ? 'warn' : 'ok';
        const title = document.createElement('p');
        title.className = 'callout-title';
        title.textContent = ic.friendlyTitle;
        const sub = document.createElement('p');
        sub.className = 'muted';
        sub.textContent = `Checked: ${ic.inputsReviewed}`;
        box.append(title, sub);
        if (Array.isArray(ic.dimensions) && ic.dimensions.length > 0) {
            const pills = document.createElement('div');
            pills.className = 'dimension-pills';
            for (const dim of ic.dimensions) {
                const span = document.createElement('span');
                span.className = 'dimension-pill';
                span.dataset.pass = String(Boolean(dim.passed));
                span.textContent = `${dim.passed ? '✓' : '!'} ${dim.name}: ${dim.note}`;
                pills.appendChild(span);
            }
            box.appendChild(pills);
        }
        intakeWrap.appendChild(box);
    } else {
        intakeWrap.hidden = true;
    }

    // Council Pre-Build Checkup Verdict Card
    const councilWrap = $('councilCheckupContainer');
    councilWrap.replaceChildren();
    if (state.councilCheckup) {
        councilWrap.hidden = false;
        const cc = state.councilCheckup;
        const box = document.createElement('section');
        box.className = 'checkup-card';
        box.dataset.state = cc.verdict === 'Stop' ? 'warn' : 'ok';
        const title = document.createElement('p');
        title.className = 'callout-title';
        title.textContent = cc.friendlyTitle;
        const note = document.createElement('p');
        note.className = 'callout-detail';
        note.textContent = cc.note;
        box.append(title, note);
        councilWrap.appendChild(box);
    } else {
        councilWrap.hidden = true;
    }

    // Pending one-question decision card
    const qWrap = $('questionCardContainer');
    qWrap.replaceChildren();
    if (state.pendingQuestion) {
        qWrap.hidden = false;
        const q = state.pendingQuestion;
        const card = document.createElement('section');
        card.className = 'question-card';

        const eyebrow = document.createElement('span');
        eyebrow.className = 'question-eyebrow';
        eyebrow.textContent = q.eyebrow || 'HVE Squad needs one quick choice';

        const h2 = document.createElement('h2');
        h2.className = 'question-title';
        h2.textContent = q.question;

        const hint = document.createElement('p');
        hint.className = 'muted';
        hint.textContent = q.plainHint;

        card.append(eyebrow, h2, hint);

        const quickActions = document.createElement('div');
        quickActions.className = 'action-row';

        if (q.recommendedChoice) {
            const recBtn = document.createElement('button');
            recBtn.type = 'button';
            recBtn.className = 'primary-btn';
            recBtn.textContent = `Use recommended: ${q.recommendedChoice.replace(/\s*\(Recommended\)/i, '')}`;
            recBtn.addEventListener('click', async () => {
                const res = await apiPost('/api/question/answer', {
                    requestId: q.requestId,
                    answer: q.recommendedChoice,
                    wasFreeform: false,
                });
                showToast('Sent your choice to HVE Squad.');
                renderAll(res.state);
            });
            quickActions.appendChild(recBtn);
        }

        if (q.skipChoice) {
            const skipBtn = document.createElement('button');
            skipBtn.type = 'button';
            skipBtn.className = 'ghost-btn';
            skipBtn.textContent = q.skipChoice;
            skipBtn.addEventListener('click', async () => {
                const res = await apiPost('/api/question/answer', {
                    requestId: q.requestId,
                    answer: q.skipChoice,
                    wasFreeform: false,
                });
                showToast('Skipped optional checkup and kept moving.');
                renderAll(res.state);
            });
            quickActions.appendChild(skipBtn);
        }

        if (quickActions.childNodes.length > 0) {
            card.appendChild(quickActions);
        }

        if (Array.isArray(q.choices) && q.choices.length > 0) {
            const choicesDiv = document.createElement('div');
            choicesDiv.className = 'question-choices';
            for (const choiceText of q.choices) {
                const cBtn = document.createElement('button');
                cBtn.type = 'button';
                cBtn.className = 'question-choice-btn';
                cBtn.textContent = choiceText;
                cBtn.addEventListener('click', async () => {
                    const res = await apiPost('/api/question/answer', {
                        requestId: q.requestId,
                        answer: choiceText,
                        wasFreeform: false,
                    });
                    showToast('Sent your choice to HVE Squad.');
                    renderAll(res.state);
                });
                choicesDiv.appendChild(cBtn);
            }
            card.appendChild(choicesDiv);
        }

        if (q.allowFreeform !== false) {
            const freeWrap = document.createElement('div');
            freeWrap.className = 'field-block';
            const input = document.createElement('input');
            input.type = 'text';
            input.className = 'text-input';
            input.placeholder = 'Or type your own answer in plain words…';
            const sendFree = document.createElement('button');
            sendFree.type = 'button';
            sendFree.className = 'secondary-btn';
            sendFree.textContent = 'Send custom answer';
            sendFree.addEventListener('click', async () => {
                if (!input.value.trim()) return;
                const res = await apiPost('/api/question/answer', {
                    requestId: q.requestId,
                    answer: input.value.trim(),
                    wasFreeform: true,
                });
                showToast('Sent your answer to HVE Squad.');
                renderAll(res.state);
            });
            freeWrap.append(input, sendFree);
            card.appendChild(freeWrap);
        }

        qWrap.appendChild(card);
    } else {
        qWrap.hidden = true;
    }

    // Run status chip & milestones
    const isWorking = state.agentStatus?.busy || state.milestones?.some((m) => m.status === 'active');
    $('runStateChip').textContent = state.pendingQuestion
        ? 'Waiting for your choice'
        : isWorking
            ? 'Working now'
            : (state.chosenSquad?.initialized ? 'Up to date' : 'Ready to start');

    const mList = $('milestonesList');
    mList.replaceChildren();
    if (!state.milestones || state.milestones.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'empty-box';
        empty.textContent = 'Start a goal in Step 1 ("What to Build") to follow plain-English progress updates here.';
        mList.appendChild(empty);
    } else {
        for (const m of state.milestones) {
            const row = document.createElement('div');
            row.className = 'milestone-item';
            row.dataset.status = m.status;
            const iconSpan = document.createElement('span');
            iconSpan.className = 'milestone-icon';
            const iconId = m.status === 'done'
                ? 'check'
                : m.status === 'waiting'
                    ? 'hand'
                    : m.status === 'active'
                        ? 'active'
                        : 'clock';
            iconSpan.appendChild(svgIcon(iconId));

            const body = document.createElement('div');
            const title = document.createElement('p');
            title.className = 'milestone-title';
            title.textContent = m.title;
            const detail = document.createElement('p');
            detail.className = 'milestone-detail';
            detail.textContent = m.detail;
            body.append(title, detail);
            row.append(iconSpan, body);
            mList.appendChild(row);
        }
    }

    // Chosen squad
    const squad = state.chosenSquad || {};
    $('chosenSquadSubtitle').textContent = squad.initialized
        ? `${squad.profileTitle} · Coordinated by HVE Squad`
        : 'HVE Squad will assemble the right specialists for your goal automatically';

    const spendPill = $('spendingSummaryPill');
    if (squad.spending && (squad.spending.estCostUsd > 0 || squad.spending.ceilingUsd !== null)) {
        spendPill.hidden = false;
        spendPill.textContent = squad.spending.ceilingUsd !== null
            ? `Est. $${squad.spending.estCostUsd.toFixed(2)} of $${squad.spending.ceilingUsd} limit`
            : `Est. spend $${squad.spending.estCostUsd.toFixed(2)}`;
    } else {
        spendPill.hidden = true;
    }

    const squadPacksEl = $('chosenSquadPacks');
    squadPacksEl.replaceChildren();
    if (Array.isArray(squad.activePacks) && squad.activePacks.length > 0) {
        squadPacksEl.hidden = false;
        for (const p of squad.activePacks) {
            const pill = document.createElement('span');
            pill.className = 'file-pill';
            pill.appendChild(svgIcon('puzzle'));
            pill.appendChild(document.createTextNode(`Specialist add-on: ${p.title}`));
            squadPacksEl.appendChild(pill);
        }
    } else {
        squadPacksEl.hidden = true;
    }

    const memberGrid = $('chosenSquadMembers');
    memberGrid.replaceChildren();
    if (!squad.members || squad.members.length === 0) {
        const emptyM = document.createElement('div');
        emptyM.className = 'empty-box';
        emptyM.textContent = 'No manual setup needed — your chosen squad will appear here as soon as HVE Squad begins.';
        memberGrid.appendChild(emptyM);
    } else {
        for (const member of squad.members) {
            const mCard = document.createElement('div');
            mCard.className = 'member-card';
            const name = document.createElement('div');
            name.className = 'member-name';
            name.textContent = member.friendlyName;
            const desc = document.createElement('div');
            desc.className = 'member-desc';
            desc.textContent = member.roleSummary;
            mCard.append(name, desc);
            memberGrid.appendChild(mCard);
        }
    }

    // Decisions
    const decSec = $('decisionsSection');
    const decList = $('decisionsList');
    decList.replaceChildren();
    if (state.decisions && state.decisions.length > 0) {
        decSec.hidden = false;
        for (const dec of state.decisions) {
            const dCard = document.createElement('div');
            dCard.className = 'decision-card';
            const dt = document.createElement('div');
            dt.className = 'member-name';
            dt.textContent = dec.title;
            const ds = document.createElement('div');
            ds.className = 'member-desc';
            ds.textContent = dec.summary;
            dCard.append(dt, ds);
            decList.appendChild(dCard);
        }
    } else {
        decSec.hidden = true;
    }
}

function renderResultsTab(state) {
    const summaryBanner = $('latestSummaryCard');
    summaryBanner.replaceChildren();
    if (state.latestSummary) {
        summaryBanner.hidden = false;
        const h2 = document.createElement('h2');
        h2.textContent = 'Plain-English Summary';
        const p = document.createElement('p');
        p.textContent = state.latestSummary;
        summaryBanner.append(h2, p);
    } else {
        summaryBanner.hidden = true;
    }

    const grid = $('deliverablesGrid');
    grid.replaceChildren();
    if (!state.deliverables || state.deliverables.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'empty-box';
        empty.textContent = 'Finished websites, presentations, plans, and guides created by your chosen squad will show up here as clickable cards.';
        grid.appendChild(empty);
    } else {
        for (const item of state.deliverables) {
            const card = document.createElement('article');
            card.className = 'deliverable-card';

            const top = document.createElement('div');
            const type = document.createElement('div');
            type.className = 'deliverable-type';
            type.textContent = item.friendlyType;
            const title = document.createElement('h3');
            title.className = 'deliverable-title';
            title.textContent = item.title;
            const summary = document.createElement('p');
            summary.className = 'muted';
            summary.textContent = item.summary;
            top.append(type, title, summary);

            if (item.previewExcerpt) {
                const excerpt = document.createElement('p');
                excerpt.className = 'deliverable-excerpt';
                excerpt.textContent = item.previewExcerpt;
                top.appendChild(excerpt);
            }

            const actions = document.createElement('div');
            actions.className = 'action-row';

            const previewBtn = document.createElement('button');
            previewBtn.type = 'button';
            previewBtn.className = 'secondary-btn';
            previewBtn.append(svgIcon('eye'), document.createTextNode('Read Preview'));
            previewBtn.addEventListener('click', async () => {
                const res = await apiPost('/api/deliverable/preview', { relativePath: item.relativePath });
                $('previewDialogTitle').textContent = item.title;
                $('previewDialogPath').textContent = res.relativePath;
                const noteEl = $('previewDialogNote');
                if (res.note) {
                    noteEl.hidden = false;
                    noteEl.textContent = res.note;
                } else {
                    noteEl.hidden = true;
                }
                $('previewDialogContent').textContent = res.content || 'Open this file in your editor to inspect it.';
                $('previewDialog').showModal();
            });
            actions.appendChild(previewBtn);

            if (!item.isPreviewOnly) {
                const openBtn = document.createElement('button');
                openBtn.type = 'button';
                openBtn.className = 'ghost-btn';
                openBtn.append(svgIcon('open'), document.createTextNode('Open in Editor'));
                openBtn.addEventListener('click', async () => {
                    const res = await apiPost('/api/deliverable/open', { relativePath: item.relativePath });
                    showToast(res.message);
                });
                actions.appendChild(openBtn);
            }

            const tweakBtn = document.createElement('button');
            tweakBtn.type = 'button';
            tweakBtn.className = 'ghost-btn';
            tweakBtn.textContent = 'Adjust This';
            tweakBtn.addEventListener('click', () => {
                selectedDeliverablePath = item.relativePath;
                $('refinementTargetHint').textContent = `(for ${item.title})`;
                $('refinementNoteInput').focus();
            });
            actions.appendChild(tweakBtn);

            card.append(top, actions);
            grid.appendChild(card);
        }
    }

    // Refinement cards
    const refGrid = $('refinementCardsGrid');
    refGrid.replaceChildren();
    for (const ref of state.catalog.refinementActions) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'goal-card';
        btn.setAttribute('role', 'radio');
        btn.setAttribute('aria-checked', String(selectedRefinementId === ref.id));

        const title = document.createElement('span');
        title.className = 'goal-card-title';
        title.textContent = ref.label;
        const desc = document.createElement('span');
        desc.className = 'goal-card-summary';
        desc.textContent = ref.description;
        btn.append(title, desc);
        btn.addEventListener('click', () => {
            selectedRefinementId = ref.id;
            renderResultsTab(state);
        });
        refGrid.appendChild(btn);
    }
}

function renderAll(state) {
    appState = state;
    applyAppearance(state.preferences);
    renderHeader(state);
    renderCreateTab(state);
    renderProgressTab(state);
    renderResultsTab(state);
}

function wireEvents() {
    for (const tabId of ['create', 'progress', 'results']) {
        $(`tab-${tabId}`).addEventListener('click', async () => {
            const next = await apiPost('/api/draft', { activeTab: tabId });
            renderAll(next);
        });
    }

    $('modeToggleBtn').addEventListener('click', async () => {
        const nextMode = appState?.mode === 'preview' ? 'live' : 'preview';
        const next = await apiPost('/api/draft', {
            mode: nextMode,
            previewStage: nextMode === 'preview' ? 'start' : undefined,
        });
        renderAll(next);
    });

    $('exitWalkthroughBtn').addEventListener('click', async () => {
        const next = await apiPost('/api/draft', { mode: 'live' });
        renderAll(next);
    });

    $('settingsBtn').addEventListener('click', () => {
        const menu = $('settingsMenu');
        const nextOpen = menu.hidden;
        menu.hidden = !nextOpen;
        $('settingsBtn').setAttribute('aria-expanded', String(nextOpen));
    });

    $('closeSettingsBtn').addEventListener('click', () => {
        $('settingsMenu').hidden = true;
        $('settingsBtn').setAttribute('aria-expanded', 'false');
    });

    for (const radio of document.querySelectorAll('input[name="studioTheme"]')) {
        radio.addEventListener('change', async () => {
            if (!radio.checked) return;
            const res = await apiPost('/api/preferences', { theme: radio.value });
            applyAppearance(res.preferences);
        });
    }

    $('contrastToggle').addEventListener('change', async (e) => {
        const res = await apiPost('/api/preferences', {
            contrast: e.target.checked ? 'more' : 'standard',
        });
        applyAppearance(res.preferences);
    });

    $('plainTipsToggle').addEventListener('change', async (e) => {
        const res = await apiPost('/api/preferences', {
            showPlainTips: e.target.checked,
        });
        applyAppearance(res.preferences);
    });

    $('neverAutoOpenToggle').addEventListener('change', async (e) => {
        const res = await apiPost('/api/preferences', {
            neverAutoOpen: e.target.checked,
        });
        applyAppearance(res.preferences);
        showToast(e.target.checked
            ? 'Saved: HVE Squad Studio stays manual-only so chat remains undisturbed.'
            : 'Saved: Standard HVE Squad Studio behavior restored.');
    });

    $('toggleHelperBtn').addEventListener('click', async () => {
        const nextOpen = !appState?.draft?.helperOpen;
        const next = await apiPost('/api/draft', { draft: { helperOpen: nextOpen } });
        renderAll(next);
    });

    $('cancelHelperBtn').addEventListener('click', async () => {
        const next = await apiPost('/api/draft', { draft: { helperOpen: false } });
        renderAll(next);
    });

    $('applyHelperBtn').addEventListener('click', async () => {
        const answers = {
            ...(appState?.draft?.helperAnswers || {}),
            topicNote: $('helperTopicInput').value,
        };
        const res = await apiPost('/api/helper/apply', { helperAnswers: answers });
        renderAll(res.state);
        $('goalTextarea').focus();
        showToast('Filled in a plain-English goal based on your 3 choices!');
    });

    $('fillExampleBtn').addEventListener('click', async () => {
        const card = appState?.catalog?.goalCards?.find((c) => c.id === appState?.draft?.goalId)
            || appState?.catalog?.goalCards?.[0];
        if (!card) return;
        const next = await apiPost('/api/draft', {
            draft: { goalText: card.exampleGoal },
        });
        renderAll(next);
    });

    $('goalTextarea').addEventListener('input', (e) => {
        const value = e.target.value;
        clearTimeout(draftSyncTimer);
        draftSyncTimer = setTimeout(async () => {
            try {
                const updated = await apiPost('/api/draft', { draft: { goalText: value } });
                renderAll(updated);
            } catch {
                // Ignore transient typing sync errors
            }
        }, 400);
    });

    async function handleSelectedFiles(fileList) {
        const items = Array.from(fileList || []);
        for (const file of items) {
            try {
                const base64Content = await fileToBase64(file);
                const res = await apiPost('/api/upload', {
                    fileName: file.name,
                    base64Content,
                });
                renderAll(res.state);
                showToast(`Attached "${file.name}" for HVE Squad intake checkup.`);
            } catch (err) {
                showToast(err.message);
            }
        }
    }

    $('chooseFileBtn').addEventListener('click', () => {
        $('docFileInput').click();
    });

    $('docFileInput').addEventListener('change', async (e) => {
        await handleSelectedFiles(e.target.files);
        e.target.value = '';
    });

    const dropzone = $('uploadDropzone');
    dropzone.addEventListener('dragover', (e) => {
        e.preventDefault();
        dropzone.classList.add('is-dragover');
    });
    dropzone.addEventListener('dragleave', () => {
        dropzone.classList.remove('is-dragover');
    });
    dropzone.addEventListener('drop', async (e) => {
        e.preventDefault();
        dropzone.classList.remove('is-dragover');
        if (e.dataTransfer?.files?.length) {
            await handleSelectedFiles(e.dataTransfer.files);
        }
    });

    $('validateIntakeCheckbox').addEventListener('change', async (e) => {
        const next = await apiPost('/api/draft', {
            draft: { validateIntake: e.target.checked },
        });
        renderAll(next);
    });

    $('allowPackPreviewsCheckbox').addEventListener('change', async (e) => {
        const next = await apiPost('/api/draft', {
            draft: { allowPackPreviews: e.target.checked },
        });
        renderAll(next);
    });

    $('togglePacksDrawerBtn').addEventListener('click', async () => {
        const nextOpen = !appState?.draft?.packsDrawerOpen;
        const next = await apiPost('/api/draft', {
            draft: { packsDrawerOpen: nextOpen },
        });
        renderAll(next);
    });

    $('councilCheckupCheckbox').addEventListener('change', async (e) => {
        const next = await apiPost('/api/draft', {
            draft: { requestCouncilCheckup: e.target.checked },
        });
        renderAll(next);
    });

    $('toggleProfileSelectBtn').addEventListener('click', () => {
        profilePickerOpen = !profilePickerOpen;
        if (appState) renderCreateTab(appState);
    });

    $('profileOverrideSelect').addEventListener('change', async (e) => {
        const next = await apiPost('/api/draft', {
            draft: { profileOverride: e.target.value },
        });
        renderAll(next);
    });

    $('launchBtn').addEventListener('click', async () => {
        const goalText = $('goalTextarea').value.trim();
        const hasUploaded = (appState?.draft?.uploadedFiles?.length || 0) > 0;
        if (!goalText && !hasUploaded) {
            showToast('Please write a short goal, click "Try a sample idea", or attach a document first.');
            $('goalTextarea').focus();
            return;
        }
        if (appState?.mode === 'preview') {
            const next = await apiPost('/api/draft', { mode: 'preview', previewStage: 'decision' });
            showToast('Walkthrough: Pre-configured your single squad, checked your document, and paused for one quick choice.');
            renderAll(next);
            return;
        }
        const btn = $('launchBtn');
        btn.disabled = true;
        try {
            const res = await apiPost('/api/launch', {
                goalId: appState?.draft?.goalId,
                goalText,
                workingStyle: appState?.draft?.workingStyle,
                budgetStyle: appState?.draft?.budgetStyle,
                spendingLimitUsd: appState?.draft?.spendingLimitUsd,
                profileOverride: appState?.draft?.profileOverride,
                selectedPacks: appState?.draft?.selectedPacks,
                allowPackPreviews: appState?.draft?.allowPackPreviews,
                requestCouncilCheckup: appState?.draft?.requestCouncilCheckup,
                validateIntake: appState?.draft?.validateIntake,
            });
            showToast('Started with HVE Squad! Follow progress here or in chat.');
            renderAll(res.state);
        } catch (err) {
            showToast(err.message);
        } finally {
            btn.disabled = false;
        }
    });

    $('sendRefinementBtn').addEventListener('click', async () => {
        const details = $('refinementNoteInput').value.trim();
        if (appState?.mode === 'preview') {
            const next = await apiPost('/api/draft', { mode: 'preview', previewStage: 'working' });
            showToast('Walkthrough: Sent your adjustment to HVE Squad.');
            renderAll(next);
            return;
        }
        const btn = $('sendRefinementBtn');
        btn.disabled = true;
        try {
            const res = await apiPost('/api/refine', {
                refinementId: selectedRefinementId,
                details,
                deliverablePath: selectedDeliverablePath,
            });
            $('refinementNoteInput').value = '';
            showToast('Sent your adjustment to HVE Squad.');
            renderAll(res.state);
        } catch (err) {
            showToast(err.message);
        } finally {
            btn.disabled = false;
        }
    });

    $('closePreviewDialogBtn').addEventListener('click', () => {
        $('previewDialog').close();
    });
}

async function boot() {
    wireEvents();
    const res = await fetch('/api/state');
    const initial = await res.json();
    renderAll(initial);

    if (!new URLSearchParams(window.location.search).has('nosse')) {
        const events = new EventSource('/events');
        events.addEventListener('state', (ev) => {
            try {
                const updated = JSON.parse(ev.data);
                renderAll(updated);
            } catch {
                // Ignore malformed event
            }
        });
    }
}

boot().catch((err) => {
    $('agentStatusLine').textContent = err instanceof Error ? err.message : 'Could not load HVE Squad Studio.';
});
