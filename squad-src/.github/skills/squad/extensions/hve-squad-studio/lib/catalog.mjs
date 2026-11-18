// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

/**
 * Beginner-friendly goal cards, guided helper steps, plain-language controls,
 * opt-in packs, council checkups, predefined initialization defaults,
 * role translations, and safe HVE Squad prompt composition.
 */

export const PREDEFINED_INIT_DEFAULTS = Object.freeze({
    layout: 'single',
    layoutLabel: 'Single chosen squad (automatic)',
    squadRoot: '.copilot-tracking/squad',
    naming: 'skip',
    namingLabel: 'Clear specialist titles (no alias prompts)',
    notify: Object.freeze({
        approvalChannel: 'in-chat',
        enabled: false,
    }),
    notifyLabel: 'Updates & choices right here in HVE Squad Studio and chat',
});

export const CHOSEN_SQUAD_PROFILES = Object.freeze([
    {
        id: 'auto',
        title: 'Match automatically from my goal (Recommended)',
        summary: 'HVE Squad picks the right specialists automatically based on your goal and any uploaded files.',
    },
    {
        id: 'product',
        title: 'Product & Experience Squad',
        summary: 'Websites, apps, slides, roadmaps, requirements, and document intake checkups.',
    },
    {
        id: 'default',
        title: 'Everyday Builder Squad',
        summary: 'General documents, guides, small code improvements, and everyday tasks.',
    },
    {
        id: 'design',
        title: 'Design & Prototyping Squad',
        summary: 'Layouts, user experience flows, and visual prototypes.',
    },
    {
        id: 'accessibility',
        title: 'Inclusive & Accessible Squad',
        summary: 'Screen-reader friendliness, contrast, keyboard navigation, and accessibility checks.',
    },
    {
        id: 'security',
        title: 'Safety & Privacy Squad',
        summary: 'Data protection, safe defaults, privacy, and responsible AI reviews.',
    },
    {
        id: 'azure',
        title: 'Cloud Delivery Squad',
        summary: 'Cloud hosting, infrastructure templates, and cloud budget checks.',
    },
    {
        id: 'full',
        title: 'Complete All-Around Squad',
        summary: 'Every specialist discipline for large or cross-cutting projects.',
    },
]);

export const PACK_CARDS = Object.freeze([
    {
        id: 'm365-copilot',
        title: 'Microsoft 365 & Teams',
        plainWhy: 'Adds Microsoft 365 Copilot, Teams app, and SharePoint/Graph specialists and templates.',
        hasPreview: true,
        previewNote: 'Optional experimental evaluation & widget helpers stay off unless you turn them on.',
        keywords: /\b(microsoft\s*365|m365|teams\s+app|sharepoint|microsoft\s+graph|declarative\s+agent|copilot\s+extensibility)\b/i,
    },
    {
        id: 'power-platform',
        title: 'Power Apps & Power Automate',
        plainWhy: 'Adds Power Apps, Power Pages, Dataverse, and Copilot Studio specialists.',
        hasPreview: true,
        previewNote: 'Optional Copilot Studio preview helpers stay off unless you explicitly allow them.',
        keywords: /\b(power\s*apps?|power\s*automate|power\s*pages|power\s*platform|dataverse|copilot\s*studio)\b/i,
    },
    {
        id: 'dotnet',
        title: '.NET & C# Apps',
        plainWhy: 'Adds official .NET, Blazor, ASP.NET Web API, and upgrade helpers.',
        hasPreview: true,
        previewNote: 'Optional .NET 11 preview migration helpers stay off by default.',
        keywords: /\b(\.net|dotnet|blazor|asp\.net|c#|ef\s*core|nuget|csproj)\b/i,
    },
    {
        id: 'azure-functions',
        title: 'Serverless Cloud Tasks (Azure Functions)',
        plainWhy: 'Adds official helpers for background cloud triggers, webhooks, and scheduled jobs.',
        hasPreview: true,
        previewNote: 'Optional preview Functions helpers stay off by default.',
        keywords: /\b(azure\s+functions?|function\s+app|serverless\s+trigger)\b/i,
    },
    {
        id: 'aks',
        title: 'Cloud Containers (Azure Kubernetes)',
        plainWhy: 'Adds container deployment, reliability, and Kubernetes cost helpers.',
        hasPreview: false,
        previewNote: '',
        keywords: /\b(kubernetes|aks\b|k8s|helm\s+chart)\b/i,
    },
    {
        id: 'azure-cloud',
        title: 'Azure Cloud & FinOps Operations',
        plainWhy: 'Adds official Azure cost governance, cross-service diagnostics, compliance, reliability, Azure Local, and cloud migration helpers.',
        hasPreview: true,
        previewNote: 'Optional multi-rack Azure Local preview helpers stay off unless you explicitly allow them.',
        keywords: /\b(finops|azure\s+cost|azure\s+local|azure\s+stack\s+hci|azqr|zone\s+redundan|cross-cloud\s+migrat)\b/i,
    },
    {
        id: 'foundry',
        title: 'Custom AI Assistants (Microsoft Foundry)',
        plainWhy: 'Adds AI model gateway, prompt safety, and AI evaluation specialists.',
        hasPreview: false,
        previewNote: '',
        keywords: /\b(microsoft\s+foundry|azure\s+ai\s+foundry|foundry\s+iq|ai\s+gateway)\b/i,
    },
    {
        id: 'fabric',
        title: 'Data & Analytics (Microsoft Fabric)',
        plainWhy: 'Adds data warehouse, Spark, Eventhouse, and analytics pipeline helpers.',
        hasPreview: false,
        previewNote: '',
        keywords: /\b(microsoft\s+fabric|lakehouse|eventhouse|dataflow|spark\s+notebook)\b/i,
    },
    {
        id: 'aws',
        title: 'Amazon Web Services (AWS)',
        plainWhy: 'Adds AWS cloud architecture and serverless workload guidance.',
        hasPreview: false,
        previewNote: '',
        keywords: /\b(aws\b|amazon\s+web\s+services|lambda\b|cloudformation|ecs\b|eks\b)\b/i,
    },
]);

export const GOAL_CARDS = Object.freeze([
    {
        id: 'web-app',
        icon: 'globe',
        title: 'Website or Small App',
        summary: 'Create a clean web page, booking tool, tracker, or interactive dashboard.',
        placeholder: 'Example: A simple appointment booking page for my neighborhood bakery with opening hours and a contact form.',
        exampleGoal: 'Create a welcoming website for a neighborhood bakery with a menu showcase, opening hours, and a simple order inquiry form.',
        profile: 'product',
        defaultDiscovery: 'quick',
        badge: 'Popular for beginners',
    },
    {
        id: 'idea-to-plan',
        icon: 'signpost',
        title: 'Turn a Rough Idea into a Plan',
        summary: 'Shape an early idea into a step-by-step roadmap, checklist, and clear requirements.',
        placeholder: 'Example: I want to organize a community volunteering program and need a clear launch plan.',
        exampleGoal: 'Help me turn my rough idea for a customer onboarding portal into a clear step-by-step plan and requirements document.',
        profile: 'product',
        defaultDiscovery: 'standard',
        badge: 'Great first step',
    },
    {
        id: 'slides-deck',
        icon: 'presentation',
        title: 'Presentation or Slides',
        summary: 'Build a clear slide deck for a pitch, team update, training session, or workshop.',
        placeholder: 'Example: A 10-slide pitch presentation explaining our new community recycling initiative.',
        exampleGoal: 'Create a clear, engaging 8-slide presentation introducing our new team onboarding process for newcomers.',
        profile: 'product',
        defaultDiscovery: 'quick',
        badge: 'Slides (.pptx)',
    },
    {
        id: 'docs-report',
        icon: 'document',
        title: 'Document, Guide, or Report',
        summary: 'Write a polished how-to guide, business proposal, summary memo, or Word document.',
        placeholder: 'Example: A friendly welcome guide for new team members explaining their first week.',
        exampleGoal: 'Write a friendly, well-structured handbook for first-time volunteers covering schedules, safety tips, and FAQs.',
        profile: 'default',
        defaultDiscovery: 'skip',
        badge: 'Docs & guides',
    },
    {
        id: 'improve-project',
        icon: 'sparkle',
        title: 'Improve or Fix Something Existing',
        summary: 'Refresh the look, add a helpful feature, or fix something broken in this folder.',
        placeholder: 'Example: Make the existing page easier to read on phones and fix the submit button.',
        exampleGoal: 'Review the existing project in this folder, simplify confusing screens, and make it easier for first-time visitors to use.',
        profile: 'default',
        defaultDiscovery: 'skip',
        badge: 'Update existing work',
    },
    {
        id: 'review-check',
        icon: 'shield',
        title: 'Check Usability, Accessibility, or Safety',
        summary: 'Have specialists check whether your project is easy to use, accessible, and safe.',
        placeholder: 'Example: Check whether people with screen readers or low vision can easily use our site.',
        exampleGoal: 'Check this project for accessibility, clarity, and safety issues, and give me a plain-English summary of what to fix first.',
        profile: 'accessibility',
        defaultDiscovery: 'skip',
        badge: 'Quality check',
    },
]);

export const HELPER_STEPS = Object.freeze([
    {
        id: 'outcome',
        stepNumber: 1,
        question: 'What would you like to end up with?',
        hint: 'Pick the closest match — you can always adjust it later.',
        choices: [
            {
                id: 'interactive-app',
                label: 'Something people can click and use',
                detail: 'A website, calculator, tracker, dashboard, or small app.',
                goalId: 'web-app',
                phrase: 'build an easy-to-use interactive web page or small app',
            },
            {
                id: 'shareable-deck',
                label: 'Slides or a visual presentation',
                detail: 'A presentation deck to explain an idea or teach a topic.',
                goalId: 'slides-deck',
                phrase: 'create a clear, visual slide presentation',
            },
            {
                id: 'written-doc',
                label: 'A polished document or guide',
                detail: 'A step-by-step guide, proposal, report, or handout.',
                goalId: 'docs-report',
                phrase: 'draft a clear, well-organized document',
            },
            {
                id: 'clear-plan',
                label: 'A clear plan before building anything',
                detail: 'Help me organize my thoughts into steps and priorities.',
                goalId: 'idea-to-plan',
                phrase: 'turn my idea into a practical, step-by-step plan',
            },
        ],
    },
    {
        id: 'audience',
        stepNumber: 2,
        question: 'Who will use or read this?',
        hint: 'This helps HVE Squad match the right tone and level of detail.',
        choices: [
            {
                id: 'personal-team',
                label: 'Me or my small team',
                detail: 'Keep it practical, simple, and quick to maintain.',
                phrase: 'designed for me and my small team',
            },
            {
                id: 'customers-public',
                label: 'Customers, clients, or the public',
                detail: 'Make it welcoming, polished, and accessible on any device.',
                phrase: 'welcoming and easy to use for customers or everyday visitors',
            },
            {
                id: 'stakeholders',
                label: 'Leaders, partners, or reviewers',
                detail: 'Focus on clarity, key takeaways, and structured outcomes.',
                phrase: 'clear and persuasive for leadership or partners',
            },
        ],
    },
    {
        id: 'readiness',
        stepNumber: 3,
        question: 'How much do you already have ready?',
        hint: 'Choose whether HVE Squad should ask a few guiding questions first.',
        choices: [
            {
                id: 'just-an-idea',
                label: 'Just a rough idea — guide me gently (Recommended)',
                detail: 'HVE Squad asks a couple of quick questions before building.',
                discovery: 'quick',
                phrase: 'Starting from a rough idea, please keep everything simple and jargon-free.',
            },
            {
                id: 'have-files',
                label: 'I already have notes or files in this folder',
                detail: 'HVE Squad inspects your folder and gets right to work.',
                discovery: 'skip',
                phrase: 'Please look at the existing files in this folder first and build from them.',
            },
            {
                id: 'deep-questions',
                label: 'Ask me thorough questions before starting',
                detail: 'Best when you want to think through every detail together first.',
                discovery: 'standard',
                phrase: 'Please walk me through clarifying questions step by step before building.',
            },
        ],
    },
]);

export const WORKING_STYLES = Object.freeze([
    {
        id: 'guided-auto',
        label: 'Do most of the work for me (Recommended)',
        description: 'HVE Squad plans, builds, and checks the result automatically, pausing only when an important choice needs your approval.',
        sessionMode: 'autopilot',
        squadMode: 'autopilot',
    },
    {
        id: 'step-by-step',
        label: 'Check with me step by step',
        description: 'HVE Squad explains each stage in plain language and waits for your go-ahead before moving on.',
        sessionMode: 'interactive',
        squadMode: null,
    },
]);

export const BUDGET_STYLES = Object.freeze([
    {
        id: 'balanced',
        label: 'Best quality (Recommended)',
        description: 'Matches each step to the strongest specialist AI models for your chosen squad.',
        routing: 'ranked',
        depth: null,
    },
    {
        id: 'saver',
        label: 'Save budget',
        description: 'Uses cost-saving AI models wherever possible to keep usage low.',
        routing: 'economy',
        depth: null,
    },
    {
        id: 'quick',
        label: 'Quick first draft',
        description: 'Creates a lighter first version faster so you can react early.',
        routing: 'ranked',
        depth: 'quick',
    },
]);

export const SPENDING_PRESETS = Object.freeze([
    { id: 'none', label: 'No limit', usd: null },
    { id: '2', label: 'Up to $2', usd: 2 },
    { id: '5', label: 'Up to $5', usd: 5 },
    { id: '10', label: 'Up to $10', usd: 10 },
]);

export const REFINEMENT_ACTIONS = Object.freeze([
    {
        id: 'visual-polish',
        icon: 'sparkle',
        label: 'Change how it looks',
        description: 'Adjust colors, spacing, layout, or visual style.',
        promptPrefix: 'Please update how the current result looks and feels:',
        defaultNote: 'Make the design cleaner, warmer, and even easier for a beginner to scan.',
    },
    {
        id: 'add-feature',
        icon: 'plus',
        label: 'Add something new',
        description: 'Add a new section, page, slide, or helpful capability.',
        promptPrefix: 'Please add this improvement to what we built:',
        defaultNote: 'Add a helpful summary section and clear next steps.',
    },
    {
        id: 'simplify-copy',
        icon: 'document',
        label: 'Make the wording simpler',
        description: 'Rewrite text in clearer, friendlier everyday language.',
        promptPrefix: 'Please simplify the wording across the deliverables:',
        defaultNote: 'Remove any technical jargon and make every heading and button crystal clear.',
    },
    {
        id: 'fix-issue',
        icon: 'wrench',
        label: 'Fix something not working',
        description: 'Tell HVE Squad what felt broken or confusing so it can fix it.',
        promptPrefix: 'Please investigate and fix this issue in the current result:',
        defaultNote: 'Check that all buttons, links, and sections work smoothly and fix any broken parts.',
    },
]);

const ROLE_DICTIONARY = Object.freeze({
    'squad coordinator': {
        friendlyName: 'HVE Squad Coordinator',
        roleSummary: 'Organizes your chosen squad and coordinates every step',
        milestoneActive: 'Organizing your chosen squad and matching specialists to your goal',
    },
    'squad coach': {
        friendlyName: 'HVE Squad Guide',
        roleSummary: 'Helps clarify your idea and answers questions in plain language',
        milestoneActive: 'Helping shape your idea into a clear plan',
    },
    'squad researcher': {
        friendlyName: 'Research Specialist',
        roleSummary: 'Finds helpful background information and project details',
        milestoneActive: 'Exploring your folder and gathering what your chosen squad needs',
    },
    'squad lead': {
        friendlyName: 'Project Planner',
        roleSummary: 'Turns your goal into a clear, step-by-step plan',
        milestoneActive: 'Creating a simple step-by-step plan for your goal',
    },
    'squad implementor': {
        friendlyName: 'Builder',
        roleSummary: 'Creates and updates your pages, files, and features',
        milestoneActive: 'Building your project files and putting the pieces together',
    },
    'squad reviewer': {
        friendlyName: 'Quality Checker',
        roleSummary: 'Checks that everything works smoothly and matches your goal',
        milestoneActive: 'Reviewing the work to make sure everything works properly',
    },
    'squad challenger': {
        friendlyName: 'Second Opinion',
        roleSummary: 'Double-checks the plan for blind spots before building',
        milestoneActive: 'Double-checking the plan so nothing important is missed',
    },
    'squad technical writer': {
        friendlyName: 'Guide Writer',
        roleSummary: 'Writes clear, friendly documentation and summaries',
        milestoneActive: 'Writing a clear, easy-to-follow guide for your result',
    },
    'squad scribe': {
        friendlyName: 'Progress Recorder',
        roleSummary: 'Saves your chosen squad notes, decisions, and progress',
        milestoneActive: 'Saving your chosen squad progress and summary notes',
    },
    'ux ui designer': {
        friendlyName: 'Experience Designer',
        roleSummary: 'Designs friendly layouts, clear navigation, and accessible flows',
        milestoneActive: 'Designing a clean, beginner-friendly layout',
    },
    'prd builder': {
        friendlyName: 'Requirements Guide',
        roleSummary: 'Captures what your product should do in clear language',
        milestoneActive: 'Writing down clear product goals and user needs',
    },
    'prd quality reviewer': {
        friendlyName: 'Document Checkup Specialist',
        roleSummary: 'Checks uploaded documents for missing details before building',
        milestoneActive: 'Checking your uploaded document for clarity and missing details',
    },
    'brd quality reviewer': {
        friendlyName: 'Document Checkup Specialist',
        roleSummary: 'Checks uploaded business documents for completeness and clarity',
        milestoneActive: 'Checking your uploaded business notes for completeness',
    },
    'requirements advisor': {
        friendlyName: 'Document Checkup Specialist',
        roleSummary: 'Reviews uploaded notes and documents before planning begins',
        milestoneActive: 'Checking your uploaded notes so nothing important is missed',
    },
    'system architecture reviewer': {
        friendlyName: 'Structure & Design Advisor',
        roleSummary: 'Checks that the technical design is solid and maintainable',
        milestoneActive: 'Reviewing overall structure during the pre-build checkup',
    },
    'squad cost manager': {
        friendlyName: 'Budget & Cost Advisor',
        roleSummary: 'Checks cloud and AI cost impact so there are no billing surprises',
        milestoneActive: 'Checking cost and budget impact before building',
    },
    'rai planner': {
        friendlyName: 'Responsible AI Advisor',
        roleSummary: 'Checks that AI features behave safely, fairly, and transparently',
        milestoneActive: 'Checking AI safety and fairness before building',
    },
    'brd builder': {
        friendlyName: 'Business Guide',
        roleSummary: 'Captures business goals and outcomes clearly',
        milestoneActive: 'Organizing your business goals into a clear summary',
    },
    'pptx': {
        friendlyName: 'Slide Designer',
        roleSummary: 'Builds clean PowerPoint slides and visual layouts',
        milestoneActive: 'Designing and building your presentation slides',
    },
    'pptx-subagent': {
        friendlyName: 'Slide Designer',
        roleSummary: 'Builds and checks PowerPoint presentation slides',
        milestoneActive: 'Formatting and polishing your presentation slides',
    },
    'accessibility planner': {
        friendlyName: 'Accessibility Specialist',
        roleSummary: 'Ensures everyone can read, navigate, and use your result',
        milestoneActive: 'Checking readability, contrast, and keyboard friendliness',
    },
    'security planner': {
        friendlyName: 'Safety Specialist',
        roleSummary: 'Checks for safe defaults and data protection',
        milestoneActive: 'Checking safety and privacy best practices',
    },
});

const PROFILE_LABELS = Object.freeze({
    default: 'Everyday Builder Squad',
    product: 'Product & Experience Squad',
    design: 'Design & Prototyping Squad',
    accessibility: 'Inclusive & Accessible Squad',
    security: 'Safety & Review Squad',
    architecture: 'System Planning Squad',
    azure: 'Cloud Delivery Squad',
    modernization: 'Project Upgrade Squad',
    compliance: 'Compliance & Governance Squad',
    operations: 'Operations & Reliability Squad',
    full: 'Complete All-Around Squad',
});

/**
 * Normalizes single-paragraph user text safely, stripping control characters.
 *
 * @param {unknown} raw
 * @param {number} [maxLength]
 * @returns {string}
 */
export function sanitizeUserText(raw, maxLength = 2000) {
    if (typeof raw !== 'string') return '';
    return raw
        .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, ' ')
        .replace(/\r\n/g, '\n')
        .replace(/[ \t]+/g, ' ')
        .trim()
        .slice(0, maxLength);
}

/**
 * Translates an internal agent or role identifier into friendly plain language.
 *
 * @param {string} rawName
 */
export function describeRolePlainly(rawName) {
    const cleaned = String(rawName ?? '')
        .replace(/^hve-squad:/i, '')
        .replace(/[-_]+/g, ' ')
        .trim();
    const key = cleaned.toLowerCase();
    const hit = ROLE_DICTIONARY[key];
    if (hit) return { rawName: String(rawName ?? ''), ...hit };
    const titleCased = cleaned
        ? cleaned.replace(/\b\w/g, (ch) => ch.toUpperCase())
        : 'Specialist';
    return {
        rawName: String(rawName ?? ''),
        friendlyName: titleCased,
        roleSummary: 'Helps your chosen squad complete this part of your goal',
        milestoneActive: `${titleCased} is working on your request`,
    };
}

/**
 * Returns a plain-language name for the chosen squad profile.
 *
 * @param {string | null | undefined} profileId
 */
export function describeProfilePlainly(profileId) {
    if (!profileId || profileId === 'auto') return 'Matched automatically';
    const key = String(profileId).trim().toLowerCase();
    return PROFILE_LABELS[key] ?? `${key.charAt(0).toUpperCase()}${key.slice(1)} Chosen Squad`;
}

/**
 * Detects plain-language specialist add-on packs relevant to the user's goal
 * or uploaded document excerpts without overwhelming beginners when none match.
 *
 * @param {string} goalText
 * @param {Array<{ originalName?: string, excerpt?: string }>} [uploadedFiles]
 */
export function detectSuggestedPacks(goalText = '', uploadedFiles = []) {
    const combined = [
        String(goalText ?? ''),
        ...(Array.isArray(uploadedFiles)
            ? uploadedFiles.map((f) => `${f?.originalName ?? ''} ${f?.excerpt ?? ''}`)
            : []),
    ].join('\n');

    if (!combined.trim()) return [];

    const suggestions = [];
    for (const pack of PACK_CARDS) {
        const match = combined.match(pack.keywords);
        if (match) {
            suggestions.push({
                id: pack.id,
                title: pack.title,
                plainWhy: pack.plainWhy,
                hasPreview: pack.hasPreview,
                previewNote: pack.previewNote,
                matchedTerm: match[0],
            });
        }
    }
    return suggestions;
}

/**
 * Synthesizes a plain-language goal description from the 3-step Guided Helper.
 *
 * @param {{ outcomeId?: string, audienceId?: string, readinessId?: string, topicNote?: string }} answers
 */
export function composeHelperBrief(answers = {}) {
    const outcomeStep = HELPER_STEPS[0].choices.find((c) => c.id === answers.outcomeId) ?? HELPER_STEPS[0].choices[0];
    const audienceStep = HELPER_STEPS[1].choices.find((c) => c.id === answers.audienceId) ?? HELPER_STEPS[1].choices[1];
    const readinessStep = HELPER_STEPS[2].choices.find((c) => c.id === answers.readinessId) ?? HELPER_STEPS[2].choices[0];
    const topic = sanitizeUserText(answers.topicNote ?? '', 500);

    const subjectClause = topic
        ? ` about "${topic}"`
        : ' tailored to my idea';

    const goalText = `I would like HVE Squad to ${outcomeStep.phrase}${subjectClause}, ${audienceStep.phrase}. ${readinessStep.phrase}`;

    return {
        goalId: outcomeStep.goalId,
        discovery: readinessStep.discovery,
        goalText,
    };
}

/**
 * Infers the best HVE Squad profile when `profileOverride` is `auto` or omitted.
 * When uploaded documents are present with Intake Checkup enabled, ensures a profile
 * carrying `intake-validator` (`product` or `full`) is selected unless explicitly overridden.
 *
 * @param {string} goalText
 * @param {string | null | undefined} goalId
 * @param {{ hasUploadedDocs?: boolean, validateIntake?: boolean, profileOverride?: string | null }} [opts]
 */
export function inferSquadProfile(goalText, goalId, opts = {}) {
    const explicit = String(opts?.profileOverride ?? '').trim().toLowerCase();
    if (explicit && explicit !== 'auto' && PROFILE_LABELS[explicit]) {
        return explicit;
    }

    if (opts?.hasUploadedDocs && opts?.validateIntake !== false) {
        return 'product';
    }

    const card = GOAL_CARDS.find((item) => item.id === goalId);
    if (card) {
        if (card.id === 'review-check' && /\b(security|safe|vulnerability|privacy)\b/i.test(goalText)) {
            return 'security';
        }
        return card.profile;
    }
    const lower = goalText.toLowerCase();
    if (/\b(website|web page|app|dashboard|form|slides|presentation|deck|plan|roadmap)\b/.test(lower)) {
        return 'product';
    }
    if (/\b(azure|bicep|cloud\s+hosting)\b/.test(lower)) {
        return 'azure';
    }
    if (/\b(accessibility|screen reader|contrast|wcag)\b/.test(lower)) {
        return 'accessibility';
    }
    if (/\b(security|safety|privacy)\b/.test(lower)) {
        return 'security';
    }
    return 'default';
}

/**
 * Composes both the human-friendly `displayPrompt` shown in chat and the
 * structured `prompt` delivered to HVE Squad, including predefined single-squad
 * initialization defaults, uploaded intake artifacts, opt-in packs, and pre-build
 * council checkup preferences.
 *
 * @param {{
 *   goalText: string,
 *   goalId?: string | null,
 *   workingStyle?: string,
 *   budgetStyle?: string,
 *   spendingLimitUsd?: number | null,
 *   discoveryOverride?: string | null,
 *   profileOverride?: string | null,
 *   selectedPacks?: string[],
 *   allowPackPreviews?: boolean,
 *   requestCouncilCheckup?: boolean,
 *   validateIntake?: boolean,
 *   uploadedFiles?: Array<{ relativePath: string, originalName?: string }>,
 *   coordinatorSelected?: boolean,
 *   preSeeded?: boolean,
 * }} input
 */
export function composeStudioLaunch(input) {
    const uploaded = Array.isArray(input?.uploadedFiles)
        ? input.uploadedFiles.filter((f) => f && typeof f.relativePath === 'string' && f.relativePath.trim())
        : [];
    const cleanGoal = sanitizeUserText(input?.goalText, 2000)
        || (uploaded.length > 0
            ? `Review my attached document (${uploaded.map((u) => u.originalName || u.relativePath).join(', ')}) and build what it describes step by step.`
            : '');

    if (!cleanGoal) {
        throw new Error('Please describe what you would like to build, pick a starter example, or attach a document first.');
    }

    const card = GOAL_CARDS.find((item) => item.id === input?.goalId) ?? null;
    const style = WORKING_STYLES.find((item) => item.id === input?.workingStyle) ?? WORKING_STYLES[0];
    const budget = BUDGET_STYLES.find((item) => item.id === input?.budgetStyle) ?? BUDGET_STYLES[0];

    let ceiling = null;
    if (input?.spendingLimitUsd !== null && input?.spendingLimitUsd !== undefined && input?.spendingLimitUsd !== '') {
        const parsed = Number(input.spendingLimitUsd);
        if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 500) {
            throw new Error('Spending limit must be a positive dollar amount up to $500.');
        }
        ceiling = Math.round(parsed * 100) / 100;
    }

    const validPackIds = new Set(PACK_CARDS.map((p) => p.id));
    const packs = Array.isArray(input?.selectedPacks)
        ? [...new Set(input.selectedPacks.map((p) => String(p).trim().toLowerCase()).filter((p) => validPackIds.has(p)))]
        : [];
    const allowPackPreviews = Boolean(input?.allowPackPreviews);
    const validateIntake = input?.validateIntake !== false;
    const requestCouncilCheckup = Boolean(input?.requestCouncilCheckup);

    const profile = inferSquadProfile(cleanGoal, card?.id ?? null, {
        hasUploadedDocs: uploaded.length > 0,
        validateIntake,
        profileOverride: input?.profileOverride,
    });

    const discovery = uploaded.length > 0
        ? 'skip'
        : (['quick', 'standard', 'deep', 'skip'].includes(String(input?.discoveryOverride ?? ''))
            ? String(input.discoveryOverride)
            : (card?.defaultDiscovery ?? 'quick'));

    const summaryTags = [
        style.label.replace(/\s*\(Recommended\)/i, ''),
        budget.label.replace(/\s*\(Recommended\)/i, ''),
    ];
    if (uploaded.length > 0) summaryTags.push(`${uploaded.length} attached file${uploaded.length > 1 ? 's' : ''}`);
    if (packs.length > 0) {
        const names = packs.map((id) => PACK_CARDS.find((p) => p.id === id)?.title ?? id);
        summaryTags.push(names.join(', '));
    }
    if (requestCouncilCheckup) summaryTags.push('Safety & Design Checkup');
    if (ceiling !== null) summaryTags.push(`Limit $${ceiling}`);

    const displayPrompt = `HVE Squad Studio: ${cleanGoal} (${summaryTags.join(' · ')})`;

    const effectiveRequest = requestCouncilCheckup
        ? `${cleanGoal} (Please run a task-fit pre-implementation council checkup before implementation.)`
        : cleanGoal;

    const parameterLines = [
        `- request: ${JSON.stringify(effectiveRequest)}`,
        `- profile: ${profile}`,
        `- discovery: ${discovery}`,
        `- routing: ${budget.routing}`,
        '- persistence: run Write-SquadHandoff.ps1 -Quiet directly for ordinary handoffs; dispatch Scribe only for exit 2 or genuinely cold operations.',
    ];
    if (packs.length > 0) parameterLines.push(`- pack: ${packs.join(',')}`);
    if (style.squadMode) parameterLines.push(`- mode: ${style.squadMode}`);
    if (budget.depth) parameterLines.push(`- depth: ${budget.depth}`);
    if (ceiling !== null) parameterLines.push(`- cost-ceiling: ${ceiling}`);
    if (uploaded.length > 0) {
        parameterLines.push(`- inputs: ${uploaded.map((u) => u.relativePath).join(', ')}`);
    }

    const initSectionLines = input?.preSeeded
        ? [
            'Predefined initialization status: `.copilot-tracking/squad` was already initialized deterministically from the user\'s confirmed HVE Squad Studio settings (`layout=single`, `naming=skip`, `notify={approvalChannel:"in-chat",enabled:false}`). Proceed directly to Step 1 (`Read State Once`).',
        ]
        : [
            'Confirmed initialization choices from HVE Squad Studio (already confirmed by the user in the Studio UI — use these predefined choices directly without re-asking single vs federation, profile, member naming, or notification channel):',
            '- layout: single (`squadRoot: .copilot-tracking/squad`)',
            `- profile: ${profile}`,
            ...(packs.length > 0
                ? [
                    `- packs: ${packs.join(', ')}`,
                    `- packPreviewResources: ${allowPackPreviews ? 'explicitly approved by user in HVE Squad Studio' : 'NOT approved (use core stable pack skills only; decline preview skills unless asked)'}`,
                ]
                : []),
            '- naming: skip',
            '- notify: `{"approvalChannel":"in-chat","enabled":false}`',
        ];

    if (budget.routing === 'economy') {
        initSectionLines.push('- economyConsent: explicitly selected by the user via "Save budget" in HVE Squad Studio.');
    }
    if (uploaded.length > 0 && validateIntake) {
        initSectionLines.push(
            `- intakeValidation: run the Intake Gate (\`intake-validator\`) on the attached input artifact(s) (${uploaded.map((u) => `\`${u.relativePath}\``).join(', ')}) before planning or building, and ask any clarifying questions in plain beginner-friendly language.`,
        );
    }
    if (requestCouncilCheckup) {
        initSectionLines.push(
            '- preBuildCheckup: run a task-fit Council review before implementation (if any needed council role is missing from the roster, propose adding it in simple everyday words, and honor a user skip as a clean Council Waiver).',
        );
    }

    const routingHint = input?.coordinatorSelected
        ? 'Run this HVE Squad request with the following settings and explain all questions, checkups, and outcomes in clear, beginner-friendly plain English (avoid internal file paths, role slugs, or CLI flags when speaking to the user):'
        : 'Use the `squad-run` skill (or HVE Squad Coordinator) to run this HVE Squad request with the following settings, and explain all questions, checkups, and outcomes in clear, beginner-friendly plain English:';

    const prompt = `${routingHint}\n${parameterLines.join('\n')}\n\n${initSectionLines.join('\n')}`;

    return {
        cleanGoal,
        profile,
        packs,
        allowPackPreviews,
        requestCouncilCheckup,
        validateIntake,
        discovery,
        sessionMode: style.sessionMode,
        routingMode: budget.routing,
        workingStyle: style.id,
        budgetStyle: budget.id,
        spendingLimitUsd: ceiling,
        displayPrompt,
        prompt,
    };
}

/**
 * Composes a 1-click refinement message for HVE Squad.
 *
 * @param {{ refinementId: string, details?: string, deliverablePath?: string | null, workingStyle?: string }} input
 */
export function composeRefinementLaunch(input) {
    const action = REFINEMENT_ACTIONS.find((item) => item.id === input?.refinementId) ?? REFINEMENT_ACTIONS[0];
    const details = sanitizeUserText(input?.details, 1500) || action.defaultNote;
    const targetFile = sanitizeUserText(input?.deliverablePath ?? '', 260);
    const style = WORKING_STYLES.find((item) => item.id === input?.workingStyle) ?? WORKING_STYLES[0];

    const fileClause = targetFile ? ` (focusing on \`${targetFile}\`)` : '';
    const humanRequest = `${action.promptPrefix}${fileClause} ${details}`;

    return {
        sessionMode: style.sessionMode,
        displayPrompt: `HVE Squad Studio — ${action.label}: ${details}`,
        prompt: `${humanRequest}\n\nKeep explanations beginner-friendly and summarize what changed in plain English.`,
    };
}
