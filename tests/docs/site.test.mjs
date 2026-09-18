import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const docsRoot = fileURLToPath(new URL('../../docs/', import.meta.url));
const siteScript = readFileSync(join(docsRoot, 'assets/site.js'), 'utf8');
const themeScript = readFileSync(join(docsRoot, 'assets/theme.js'), 'utf8');
const pages = readdirSync(docsRoot).filter(name => name.endsWith('.html') && !name.startsWith('squad-governance-report-'));
const origin = 'https://docs.example/hve-squad/';
const load = name => readFileSync(join(docsRoot, name), 'utf8');

function openPage(name, { query = '', stored = {}, blockedStorage = false, darkSystem = false, scripts = true, html } = {}) {
  const dom = new JSDOM(html ?? load(name), { url: `${origin}${name}${query}`, runScripts: 'outside-only' });
  dom.window.matchMedia = () => ({ matches: darkSystem });
  for (const [key, value] of Object.entries(stored)) dom.window.localStorage.setItem(`hve-docs-${key}`, value);
  if (blockedStorage) Object.defineProperty(dom.window, 'localStorage', { get() { throw new Error('Storage blocked'); } });
  if (scripts) {
    dom.window.eval(themeScript);
    dom.window.eval(siteScript);
  }
  return dom;
}

function assertNoPartnerWorkshopLinks(document) {
  for (const link of document.querySelectorAll('a[href]')) {
    assert.doesNotMatch(link.href, /\/(?:onepoint-)?hve-squad-workshop(?:[/?#]|$)/i,
      'Documentation must not link to partner-specific workshops');
  }
}

const invocation = /^\s*\/squad(?:-federation|-document|-governance-report|-learn)?(?:\s|$)/m;

for (const name of pages) {
  for (const locale of ['en', 'fr']) {
    const relative = `${locale === 'fr' ? 'fr/' : ''}${name}`;
    test(`${relative}: language pair, assets, links and page structure`, () => {
      const dom = openPage(relative, { scripts: false });
      try {
        const document = dom.window.document;
        assertNoPartnerWorkshopLinks(document);
        assert.equal(document.documentElement.lang, locale);
        assert.equal(document.querySelectorAll('main').length, 1);
        assert.equal(document.querySelectorAll('h1').length, 1);
        assert.ok(document.querySelector('meta[name="description"]')?.content);
        const alternate = document.querySelector('link[rel="alternate"]');
        assert.equal(alternate.hreflang, locale === 'fr' ? 'en' : 'fr');
        assert.equal(new URL(alternate.href).pathname, `/hve-squad/${locale === 'fr' ? '' : 'fr/'}${name}`);
        const ids = [...document.querySelectorAll('[id]')].map(element => element.id);
        assert.equal(new Set(ids).size, ids.length, 'IDs must be unique');
        for (const element of document.querySelectorAll('[href], [src]')) {
          const reference = element.getAttribute('href') ?? element.getAttribute('src');
          const url = new URL(reference, `${origin}${relative}`);
          if (!url.href.startsWith(origin)) continue;
          const target = decodeURIComponent(url.pathname.slice('/hve-squad/'.length)) || 'index.html';
          assert.ok(existsSync(resolve(docsRoot, target)), `${relative}: missing ${reference}`);
          if (url.hash && target.endsWith('.html')) {
            const targetDom = new JSDOM(load(target));
            assert.ok(targetDom.window.document.getElementById(decodeURIComponent(url.hash.slice(1))), `${relative}: missing anchor ${reference}`);
            targetDom.window.close();
          }
        }
        for (const image of document.images) assert.ok(image.hasAttribute('alt'), 'Images need alt attributes');
        const scripts = [...document.querySelectorAll('script[src]')];
        assert.ok(scripts[0].src.endsWith('/assets/theme.js'), 'Theme detection precedes other scripts');
        assert.ok(scripts.some(script => script.src.endsWith('/assets/site.js') && script.defer));
        for (const code of document.querySelectorAll('code')) {
          if (code.closest('pre, [data-host-reference]')) continue;
          assert.doesNotMatch(code.textContent, /^\/squad(?:-federation|-document|-governance-report|-learn)?\s+(?:request=|init\b|promote\b|profile=|mode=|squad=)/,
            'Runnable examples belong in local command blocks, not inline prose');
        }
      } finally { dom.window.close(); }
    });

    test(`${relative}: local host panels and accessible navigation`, () => {
      const dom = openPage(relative, { query: '?host=cli' });
      try {
        const document = dom.window.document;
        assertNoPartnerWorkshopLinks(document);
        assert.equal(document.querySelector('.hero [role="tablist"]'), null);
        for (const guide of document.querySelectorAll('.host-guide')) {
          assert.equal(guide.querySelectorAll('[role="tab"]').length, 3);
          assert.equal(guide.querySelectorAll('[role="tab"][aria-selected="true"]').length, 1);
          assert.equal(guide.querySelectorAll('[role="tabpanel"]:not([hidden])').length, 1);
          assert.equal(guide.querySelector('[role="tab"][aria-selected="true"]').textContent, 'Copilot CLI');
          assert.equal(guide.parentElement.closest('.host-guide'), null, 'No nested selectors');
        }
        const ids = [...document.querySelectorAll('[id]')].map(element => element.id);
        assert.equal(new Set(ids).size, ids.length);
        for (const tab of document.querySelectorAll('[role="tab"]')) {
          const panel = document.getElementById(tab.getAttribute('aria-controls'));
          assert.equal(panel.getAttribute('aria-labelledby'), tab.id);
        }
        assert.equal(document.querySelector('.nav-links [aria-current="page"]').getAttribute('href'), name.startsWith('demo-') ? 'demo.html' : name);
        assert.equal(document.querySelector('.skip-link').getAttribute('href'), '#main');
        assert.ok(document.getElementById('main'));
        const menu = document.querySelector('.menu-toggle');
        menu.click();
        assert.equal(menu.getAttribute('aria-expanded'), 'true');
        document.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        assert.equal(menu.getAttribute('aria-expanded'), 'false');
      } finally { dom.window.close(); }
    });

    test(`${relative}: all command examples have correct host variants`, () => {
      const source = openPage(relative, { scripts: false });
      const sourceCodes = [...source.window.document.querySelectorAll('pre > code')];
      const commands = sourceCodes.filter(code => !code.closest('[data-host-reference]') && invocation.test(code.textContent)).map(code => code.textContent);
      const otherExamples = sourceCodes.filter(code => !invocation.test(code.textContent)).map(code => code.textContent);
      source.window.close();
      for (const host of ['cli', 'app', 'vscode']) {
        const dom = openPage(relative, { query: `?host=${host}` });
        try {
          const document = dom.window.document;
          const examples = [...document.querySelectorAll('.command-example')];
          assert.equal(examples.length, commands.length, 'Every runnable block gets local tabs');
          examples.forEach((example, index) => {
            const canonical = example.querySelector('[data-host="vscode"] pre code').textContent;
            assert.equal(canonical, commands[index], 'VS Code keeps the exact original example');
            const selected = example.querySelector('[role="tabpanel"]:not([hidden])');
            assert.equal(selected.dataset.host, host);
            if (host !== 'vscode') {
              const inputs = [...selected.querySelectorAll('pre code')].map(code => code.textContent);
              for (const input of inputs) {
                assert.ok(input.trim() && input !== 'undefined');
                assert.doesNotMatch(input, invocation, 'App and CLI inputs have no VS Code invocation prefix');
                assert.doesNotMatch(input, /^#|^\/agent/m, 'Selection instructions stay outside copyable inputs');
              }
              const argumentLines = canonical.split('\n').filter(line => !line.trimStart().startsWith('#')).map(line => line.replace(/^[ \t]*\/squad(?:-federation|-document|-governance-report|-learn)?(?=\s|$)[ \t]?/, '')).filter(line => line.trim());
              for (const line of argumentLines) assert.ok(inputs.join('\n').includes(line), `Preserve arguments: ${line}`);
            }
          });
          const unchanged = [...document.querySelectorAll('pre > code')].filter(code => !code.closest('.command-example')).map(code => code.textContent);
          assert.deepEqual(unchanged, otherExamples, 'Shell commands, config and paths stay unchanged');
        } finally { dom.window.close(); }
      }
    });
  }
}

function renderExample(text, lang = 'en') {
  const source = new JSDOM(`<html lang="${lang}"><body><main><pre><code></code></pre></main></body></html>`);
  source.window.document.querySelector('code').textContent = text;
  const html = source.serialize();
  source.window.close();
  return openPage('usage.html', { html, query: '?host=cli' });
}

test('each workflow selects its own agent, including requests with no arguments', () => {
  const workflows = [
    ['/squad init', 'Squad Coordinator', 'init'],
    ['/squad-federation promote', 'Squad Federation Coordinator', 'promote'],
    ['/squad-document request="summarize" format=html', 'Squad Document', 'request="summarize" format=html'],
    ['/squad-governance-report', 'Squad Governance Report', 'Generate the governance report with default settings.'],
    ['/squad-learn', 'Squad Learn', 'Help me propose a shared learning.']
  ];
  const dom = renderExample(workflows.map(([command]) => command).join('\n'));
  try {
    for (const host of ['cli', 'app']) {
      const panel = dom.window.document.querySelector(`[data-host="${host}"]`);
      assert.deepEqual([...panel.querySelectorAll('strong')].map(agent => agent.textContent), workflows.map(([, agent]) => agent));
      assert.deepEqual([...panel.querySelectorAll('pre code')].map(code => code.textContent), workflows.map(([, , input]) => input));
      assert.equal(panel.textContent.includes('/agent'), host === 'cli');
    }
  } finally { dom.window.close(); }
});

test('multiline quoted content, embedded slash commands and escaped quotes remain literal', () => {
  const argumentsText = 'request="Keep this exact text:\n\n/squad-learn is a literal example\n# not a comment here\nUse \\"quoted\\" text and .copilot-tracking/squad/." mode=autopilot cost-ceiling=20';
  const dom = renderExample(`/squad ${argumentsText}`);
  try {
    for (const host of ['cli', 'app']) {
      const inputs = dom.window.document.querySelectorAll(`[data-host="${host}"] pre code`);
      assert.equal(inputs.length, 1);
      assert.equal(inputs[0].textContent, argumentsText);
    }
  } finally { dom.window.close(); }
});

test('formatter indentation and comments do not hide executable examples', () => {
  const dom = renderExample('# First request\n    /squad init\n\n    # A separate federation request\n    /squad-federation promote');
  try {
    const panel = dom.window.document.querySelector('[data-host="cli"]');
    assert.deepEqual([...panel.querySelectorAll('pre code')].map(code => code.textContent), ['init', 'promote']);
    assert.deepEqual([...panel.querySelectorAll('.command-note')].map(note => note.textContent), ['First request', 'A separate federation request']);
  } finally { dom.window.close(); }
});

test('non-command snippets and explicit host references are not converted', () => {
  for (const text of ['gh issue comment 42 --body "/squad review"', '.github/skills/squad/squad-watch.workflow.yml', '/squad-doctor', '/squad request="unfinished']) {
    const dom = renderExample(text);
    try {
      assert.equal(dom.window.document.querySelector('.command-example'), null);
      assert.equal(dom.window.document.querySelector('pre code').textContent, text);
    } finally { dom.window.close(); }
  }
  const dom = openPage('usage.html', { html: '<main><pre data-host-reference><code>/squad request="VS Code reference"</code></pre></main>' });
  try { assert.equal(dom.window.document.querySelector('.command-example'), null); }
  finally { dom.window.close(); }
});

test('local command examples select the correct agent and preserve request arguments', () => {
  const dom = openPage('fr/usage.html', { query: '?host=app' });
  try {
    const document = dom.window.document;
    assert.equal(document.querySelector('.hero [role="tablist"]'), null);
    const examples = [...document.querySelectorAll('.command-example')];
    assert.ok(examples.length > 1);
    const mixed = examples.find(example => example.querySelector('[data-host="vscode"]').textContent.includes('/squad-document request='));
    const app = mixed.querySelector('[data-host="app"]');
    assert.equal(app.hidden, false);
    assert.match(app.textContent, /Squad Document/);
    assert.match(app.textContent, /Squad Governance Report/);
    for (const code of app.querySelectorAll('pre code')) assert.doesNotMatch(code.textContent, /^\/squad/m);
    assert.match(app.textContent, /format=docx outputPath=docs\/synthese.docx/);
    assert.match(app.textContent, /period=30d output=docs\/gouvernance.html/);
  } finally { dom.window.close(); }
});

test('host tabs support arrow keys, Home, End, focus and persistence', () => {
  const dom = openPage('getting-started.html', { query: '?host=cli' });
  try {
    const document = dom.window.document;
    const tabs = [...document.querySelector('.command-example').querySelectorAll('[role="tab"]')];
    tabs[0].focus();
    for (const [key, expected] of [['ArrowLeft', 2], ['Home', 0], ['End', 2], ['ArrowRight', 0], ['ArrowRight', 1]]) {
      document.activeElement.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
      assert.equal(document.activeElement, tabs[expected]);
      assert.equal(tabs[expected].getAttribute('aria-selected'), 'true');
      assert.equal(tabs[expected].tabIndex, 0);
    }
    assert.equal(dom.window.localStorage.getItem('hve-docs-host'), 'app');
    assert.equal(new URL(dom.window.location.href).searchParams.get('host'), 'app');
    for (const tab of document.querySelectorAll('[role="tab"][aria-selected="true"]')) {
      assert.equal(tab.textContent, 'Copilot App', 'Selections stay synchronized without moving focus');
    }
  } finally { dom.window.close(); }
});

for (const name of ['getting-started.html', 'fr/getting-started.html']) {
  test(`${name}: every installation path is readable without scripts`, () => {
    const dom = openPage(name, { scripts: false });
    try {
      const panels = [...dom.window.document.querySelectorAll('.host-guide > [data-host]')];
      assert.equal(panels.length, 3);
      for (const panel of panels) {
        assert.equal(panel.hidden, false);
        assert.ok(panel.querySelector('p'));
      }
    } finally { dom.window.close(); }
  });
}

test('stored preferences apply and explicit valid URL choices win', () => {
  for (const [query, host, theme] of [['', 'app', 'dark'], ['?host=cli&scoutTheme=light', 'cli', 'light']]) {
    const dom = openPage('getting-started.html', { query, stored: { host: 'app', theme: 'dark' } });
    try {
      assert.equal(dom.window.document.querySelector('[role="tabpanel"]:not([hidden])').dataset.host, host);
      assert.equal(dom.window.document.documentElement.dataset.theme, theme);
      dom.window.document.querySelector('.theme-control input').click();
      assert.equal(dom.window.localStorage.getItem('hve-docs-theme'), theme === 'dark' ? 'light' : 'dark');
    } finally { dom.window.close(); }
  }
});

test('invalid parameters and unavailable storage do not break the page', () => {
  const dom = openPage('fr/getting-started.html', { query: '?host=unknown&scoutTheme=unknown', blockedStorage: true, darkSystem: true });
  try {
    assert.equal(dom.window.document.documentElement.dataset.theme, 'dark');
    assert.equal(dom.window.document.querySelector('[role="tabpanel"]:not([hidden])').dataset.host, 'vscode');
    dom.window.document.querySelector('[role="tab"]').click();
    assert.equal(dom.window.document.querySelector('[role="tabpanel"]:not([hidden])').dataset.host, 'cli');
  } finally { dom.window.close(); }
});