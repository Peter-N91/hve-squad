// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
// SPDX-License-Identifier: MIT

import { describeProfilePlainly, describeRolePlainly } from './catalog.mjs';

export const PREVIEW_STAGES = Object.freeze([
    'start',
    'intake-addons',
    'helper',
    'decision',
    'working',
    'results',
]);

/**
 * Builds rich, realistic interactive walkthrough snapshots so beginners can preview
 * how HVE Squad Studio works without AI cost, and reviewers can inspect every screen.
 *
 * @param {string} stage
 */
export function buildPreviewSnapshot(stage = 'start') {
    const normalized = PREVIEW_STAGES.includes(stage) ? stage : 'start';

    const chosenSquadMembers = [
        describeRolePlainly('UX UI Designer'),
        describeRolePlainly('Squad Lead'),
        describeRolePlainly('Squad Implementor'),
        describeRolePlainly('Squad Reviewer'),
        describeRolePlainly('Squad Technical Writer'),
    ];

    const base = {
        mode: 'preview',
        previewStage: normalized,
        activeTab: 'create',
        agentStatus: {
            connected: true,
            selectedAgent: 'Squad Coordinator',
            friendlyAgent: 'HVE Squad Coordinator (automatic)',
            sessionMode: 'autopilot',
            note: 'Interactive preview — explore how HVE Squad Studio guides you before starting a real run.',
        },
        chosenSquad: {
            initialized: normalized !== 'start' && normalized !== 'intake-addons' && normalized !== 'helper',
            profileId: 'product',
            profileTitle: describeProfilePlainly('product'),
            activePacks: normalized === 'decision' || normalized === 'working' || normalized === 'results'
                ? [{ id: 'm365-copilot', title: 'Microsoft 365 & Teams' }]
                : [],
            turn: normalized === 'results' ? 3 : (normalized === 'start' || normalized === 'intake-addons' || normalized === 'helper' ? 0 : 1),
            spending: {
                estCostUsd: normalized === 'results' ? 0.42 : (normalized === 'working' || normalized === 'decision' ? 0.14 : 0),
                ceilingUsd: 5,
                remainingUsd: normalized === 'results' ? 4.58 : 4.86,
            },
            members: chosenSquadMembers,
        },
        draft: {
            goalId: 'web-app',
            goalText: normalized === 'start'
                ? ''
                : normalized === 'intake-addons'
                    ? 'Create an internal catering request portal for Sunny Crumb Bakery that also posts new catering orders into Microsoft Teams.'
                    : 'Create a welcoming website for Sunny Crumb Bakery with our daily bread menu, opening hours, and a simple cake pre-order form.',
            workingStyle: 'guided-auto',
            budgetStyle: 'balanced',
            spendingLimitUsd: 5,
            profileOverride: 'auto',
            selectedPacks: normalized === 'intake-addons' ? ['m365-copilot'] : [],
            allowPackPreviews: false,
            packsDrawerOpen: false,
            requestCouncilCheckup: normalized === 'intake-addons' || normalized === 'decision',
            validateIntake: true,
            uploadedFiles: normalized === 'intake-addons'
                ? [
                    {
                        relativePath: '.copilot-tracking/studio-inputs/bakery-catering-notes.docx',
                        originalName: 'bakery-catering-notes.docx',
                        sizeBytes: 48210,
                        excerpt: 'Catering menu tiers, lead-time rules, and Microsoft Teams order alerts for bakery staff.',
                    },
                ]
                : [],
            helperOpen: normalized === 'helper',
            helperAnswers: {
                outcomeId: 'interactive-app',
                audienceId: 'customers-public',
                readinessId: 'just-an-idea',
                topicNote: 'Sunny Crumb Bakery menu and cake pre-orders',
            },
        },
        intakeCheckup: null,
        councilCheckup: null,
        pendingQuestion: null,
        hostPermissionPending: null,
        milestones: [],
        decisions: [],
        deliverables: [],
        latestSummary: null,
    };

    if (normalized === 'decision') {
        base.activeTab = 'progress';
        base.intakeCheckup = {
            verdict: 'Ready-With-Gaps',
            friendlyTitle: 'Document Checkup: Ready (helpful assumptions noted)',
            inputsReviewed: 'bakery-catering-notes.docx',
            dimensions: [
                { name: 'Completeness', passed: true, note: 'Menu tiers and pickup lead times found' },
                { name: 'Clarity', passed: true, note: 'Looks clear' },
                { name: 'Testability', passed: true, note: 'Order confirmation criteria clear' },
                { name: 'Consistency', passed: true, note: 'Looks clear' },
                { name: 'Scope Boundaries', passed: true, note: 'Assumed in-store payment for v1' },
            ],
        };
        base.pendingQuestion = {
            requestId: 'preview-question-1',
            kind: 'council',
            eyebrow: 'Extra Safety, Budget & Design Checkup Suggested',
            question: 'Because this portal sends customer order details to Microsoft Teams, would you like Safety and Budget specialists to double-check the plan before building?',
            plainHint: 'HVE Squad noticed customer data and platform integration. Skipping records a clean waiver and will not block your project.',
            recommendedChoice: 'Yes, run the Safety & Budget checkup before building (Recommended)',
            skipChoice: 'Skip extra checkup and start building now',
            choices: [
                'Yes, run the Safety & Budget checkup before building (Recommended)',
                'Only run the Safety checkup',
                'Skip extra checkup and start building now',
            ],
            allowFreeform: true,
        };
        base.hostPermissionPending = {
            active: true,
            title: 'One-time safety check in the main window',
            detail: 'When HVE Squad is ready to save files or start a local preview, GitHub Copilot may show an "Allow" button in the chat panel for your security.',
        };
        base.milestones = [
            {
                id: 'm-1',
                status: 'done',
                title: 'Pre-configured your single squad & checked bakery-catering-notes.docx',
                detail: 'Document Checkup Specialist confirmed your attached notes are ready to build from.',
            },
            {
                id: 'm-2',
                status: 'waiting',
                title: 'Waiting for your quick checkup choice above',
                detail: 'Approve the recommended Safety & Budget checkup, or skip it to build right away.',
            },
            {
                id: 'm-3',
                status: 'upcoming',
                title: 'Design and build the bakery pages',
                detail: 'Experience Designer and Builder will create your menu, hours, and pre-order section.',
            },
        ];
    } else if (normalized === 'working') {
        base.activeTab = 'progress';
        base.intakeCheckup = {
            verdict: 'Ready',
            friendlyTitle: 'Document Checkup: Ready to Build',
            inputsReviewed: 'bakery-catering-notes.docx',
            dimensions: [
                { name: 'Completeness', passed: true, note: 'Looks clear' },
                { name: 'Clarity', passed: true, note: 'Looks clear' },
                { name: 'Testability', passed: true, note: 'Looks clear' },
            ],
        };
        base.councilCheckup = {
            verdict: 'Go-With-Conditions',
            friendlyTitle: 'Pre-Build Checkup: Approved with helpful guardrails',
            members: 'Safety Specialist, Budget & Cost Advisor',
            note: 'Avoid posting customer phone numbers in shared Teams channels; show order IDs instead.',
        };
        base.milestones = [
            {
                id: 'm-1',
                status: 'done',
                title: 'Planned your Sunny Crumb Bakery website',
                detail: 'Project Planner organized the page into Hero Welcome, Daily Bread Menu, Hours & Map, and Pre-Order Form.',
            },
            {
                id: 'm-2',
                status: 'done',
                title: 'Designed a warm, mobile-friendly layout',
                detail: 'Experience Designer selected readable fonts, high-contrast buttons, and phone-friendly cards.',
            },
            {
                id: 'm-3',
                status: 'active',
                title: 'Building the interactive pre-order form',
                detail: 'Builder is wiring date pickup selection and instant order confirmation.',
            },
            {
                id: 'm-4',
                status: 'upcoming',
                title: 'Quality & accessibility check',
                detail: 'Quality Checker will verify keyboard navigation, mobile layout, and form messages.',
            },
        ];
        base.decisions = [
            {
                title: 'Simple on-page pre-order form selected',
                summary: 'Customers can pick a pickup day, choose pastries or custom cake size, and see an instant confirmation.',
            },
        ];
    } else if (normalized === 'results') {
        base.activeTab = 'results';
        base.latestSummary = 'Your chosen squad finished building the Sunny Crumb Bakery website, checked that every button and form works on phones and computers, and wrote a short plain-English guide showing how to edit your daily menu.';
        base.milestones = [
            {
                id: 'm-1',
                status: 'done',
                title: 'Planned your Sunny Crumb Bakery website',
                detail: '4 clear sections tailored for local customers.',
            },
            {
                id: 'm-2',
                status: 'done',
                title: 'Built the website and cake pre-order form',
                detail: 'Created clean HTML, warm bakery styling, and form validation.',
            },
            {
                id: 'm-3',
                status: 'done',
                title: 'Checked quality and mobile friendliness',
                detail: 'Passed readability, contrast, and keyboard checks with zero blockers.',
            },
        ];
        base.decisions = [
            {
                title: 'Mobile-first menu cards & simple pre-order form',
                summary: 'Kept everything self-contained so you can open it in any browser with double-click.',
            },
        ];
        base.deliverables = [
            {
                id: 'deliv-1',
                kind: 'web',
                title: 'Sunny Crumb Bakery Website',
                friendlyType: 'Interactive Web Page',
                relativePath: 'outputs/bakery-site/index.html',
                summary: 'Complete homepage with daily bread menu, opening hours, and interactive cake pre-order form.',
                previewExcerpt: 'Welcome to Sunny Crumb Bakery — Fresh sourdough at 7 AM daily • Browse Today’s Bake • Pre-Order a Celebration Cake.',
                isPreviewOnly: true,
            },
            {
                id: 'deliv-2',
                kind: 'doc',
                title: 'How to Update Your Menu & Hours',
                friendlyType: 'Plain-English Owner Guide',
                relativePath: 'docs/owner-guide.md',
                summary: 'Step-by-step guide showing exactly where to change prices, seasonal items, and holiday hours.',
                previewExcerpt: '1. Open index.html • 2. Look for the "Daily Menu" list • 3. Change any item name or price and save.',
                isPreviewOnly: true,
            },
            {
                id: 'deliv-3',
                kind: 'plan',
                title: 'Quality & Accessibility Check Summary',
                friendlyType: 'Checkup Report',
                relativePath: 'docs/quality-summary.md',
                summary: 'Confirms high-contrast text, mobile phone layout, and clear form error messages.',
                previewExcerpt: 'All 6 beginner usability and WCAG contrast checks passed.',
                isPreviewOnly: true,
            },
        ];
    }

    return base;
}