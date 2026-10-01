import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const script = readFileSync(new URL('../../site/assets/hosts.js', import.meta.url), 'utf8');
const locales = JSON.parse(readFileSync(new URL('../../site/host-locales.json', import.meta.url), 'utf8'));
const hosts = ['cli', 'app', 'vscode'];
const manualGuide = `<div class="host-guide installation-guide">
  <section data-host="cli" id="install-cli"><p>Install CLI.</p><pre><code>/squad init</code></pre></section>
  <section data-host="app"><p>Install App.</p></section>
  <section data-host="vscode"><p>Install VS Code.</p></section>
</div>`;

function openPage({
  lang = 'en', html = '', examples = [], query = '', stored, blockedStorage = false,
  config = { host: locales }, scripts = true
} = {}) {
  const dom = new JSDOM(`<html><body><main>${html}</main></body></html>`, {
    url: `https://docs.example/hve-squad/usage.html${query}`,
    runScripts: 'outside-only'
  });
  const { window } = dom;
  const { document } = window;
  document.documentElement.lang = lang;
  if (config !== null) {
    const node = document.createElement('script');
    node.type = 'application/json';
    node.id = 'site-ui';
    node.textContent = typeof config === 'string' ? config : JSON.stringify(config);
    document.body.append(node);
  }
  for (const text of examples) {
    const pre = document.createElement('pre');
    const code = document.createElement('code');
    code.textContent = text;
    pre.append(code);
    document.querySelector('main').append(pre);
  }
  if (stored !== undefined) window.localStorage.setItem('hve-docs-host', stored);
  if (blockedStorage) {
    Object.defineProperty(window, 'localStorage', {
      get() { throw new Error('Storage blocked'); }
    });
  }
  const scrolls = [];
  window.scrollBy = options => scrolls.push({ ...options });
  const ready = [];
  document.addEventListener('hve-content-ready', () => {
    ready.push({
      examples: document.querySelectorAll('.command-example').length,
      tabs: document.querySelectorAll('[role="tab"]').length,
      pre: document.querySelectorAll('pre').length
    });
  });
  const run = () => window.eval(script);
  if (scripts) {
    try { run(); }
    catch (error) { window.close(); throw error; }
  }
  return { dom, window, document, scrolls, ready, run };
}

const codes = panel => [...panel.querySelectorAll('pre > code')].map(code => code.textContent);
const panelFor = (document, host) => document.querySelector(`.command-example > [data-host="${host}"]`);
const tabsFor = guide => [...guide.querySelectorAll(':scope > [role="tablist"] > [role="tab"]')];

function assertSelected(document, host) {
  for (const guide of document.querySelectorAll('.host-guide')) {
    const tabs = tabsFor(guide);
    assert.equal(tabs.length, 3);
    assert.equal(tabs.filter(tab => tab.tabIndex === 0).length, 1);
    assert.equal(tabs.filter(tab => tab.getAttribute('aria-selected') === 'true').length, 1);
    const panels = [...guide.querySelectorAll(':scope > [role="tabpanel"]')];
    assert.deepEqual(panels.filter(panel => !panel.hidden).map(panel => panel.dataset.host), [host]);
    for (const tab of tabs) {
      const panel = document.getElementById(tab.getAttribute('aria-controls'));
      assert.ok(panel);
      assert.equal(panel.getAttribute('aria-labelledby'), tab.id);
      assert.equal(panel.tabIndex, 0);
      assert.equal(tab.getAttribute('aria-selected'), String(!panel.hidden));
      assert.equal(tab.tabIndex, panel.hidden ? -1 : 0);
    }
  }
}

for (const lang of ['en', 'fr']) {
  test(`${lang}: each workflow selects its own agent and preserves named and positional arguments`, () => {
    const workflows = [
      ['/squad', 'Squad Coordinator', locales[lang].defaultRequests['/squad']],
      ['/squad init', 'Squad Coordinator', 'init'],
      ['/squad request="Review this" mode=autopilot cost-ceiling=20', 'Squad Coordinator', 'request="Review this" mode=autopilot cost-ceiling=20'],
      ['/squad-federation', 'Squad Federation Coordinator', locales[lang].defaultRequests['/squad-federation']],
      ['/squad-federation promote', 'Squad Federation Coordinator', 'promote'],
      ['/squad-document request="summarize" format=html outputPath=docs/summary.html', 'Squad Document', 'request="summarize" format=html outputPath=docs/summary.html'],
      ['/squad-governance-report', 'Squad Governance Report', locales[lang].defaultRequests['/squad-governance-report']],
      ['/squad-governance-report period=30d output=docs/report.html', 'Squad Governance Report', 'period=30d output=docs/report.html'],
      ['/squad-learn', 'Squad Learn', locales[lang].defaultRequests['/squad-learn']],
      ['/squad-learn request="Remember this" squad=local', 'Squad Learn', 'request="Remember this" squad=local']
    ];
    const canonical = workflows.map(([command]) => command).join('\n');
    const { window, document } = openPage({ lang, examples: [canonical] });
    try {
      for (const host of ['cli', 'app']) {
        const panel = panelFor(document, host);
        assert.deepEqual(codes(panel), workflows.map(([, , input]) => input));
        assert.deepEqual([...panel.querySelectorAll('strong')].map(agent => agent.textContent), workflows.map(([, agent]) => agent));
        assert.equal(panel.textContent.includes('/agent'), host === 'cli');
        for (const input of codes(panel)) {
          assert.ok(input.trim());
          assert.notEqual(input, 'undefined');
          assert.doesNotMatch(input, /^\/squad(?:\s|-)/);
        }
      }
      assert.deepEqual(codes(panelFor(document, 'vscode')), [canonical]);
      assert.equal(document.querySelector('[role="tablist"]').getAttribute('aria-label'), locales[lang].tablistLabel);
      for (const host of hosts) {
        const instruction = panelFor(document, host).querySelector('.command-instruction').textContent;
        assert.equal(instruction, locales[lang].instructions[host].replace('{agent}', 'Squad Coordinator'));
      }
    } finally { window.close(); }
  });
}

test('default request translations retain their original English and French wording', () => {
  assert.deepEqual(locales.en.defaultRequests, {
    '/squad': 'Initialize the squad.',
    '/squad-federation': 'Initialize the federation.',
    '/squad-governance-report': 'Generate the governance report with default settings.',
    '/squad-learn': 'Help me propose a shared learning.'
  });
  assert.deepEqual(locales.fr.defaultRequests, {
    '/squad': 'Initialise la squad.',
    '/squad-federation': 'Initialise la fédération.',
    '/squad-governance-report': 'Génère le rapport de gouvernance avec les paramètres par défaut.',
    '/squad-learn': 'Aide-moi à proposer un apprentissage partagé.'
  });
});

test('multiline requests retain blank lines, embedded commands, comments and escaped quotes', () => {
  const input = 'request="Keep this exact text:\n\n/squad-learn is a literal example\n# not a comment here\nUse \\"quoted\\" text and .copilot-tracking/squad/." mode=autopilot cost-ceiling=20';
  const canonical = `/squad ${input}\n/squad-federation promote`;
  const { window, document } = openPage({ examples: [canonical] });
  try {
    for (const host of ['cli', 'app']) {
      assert.deepEqual(codes(panelFor(document, host)), [input, 'promote']);
      assert.equal(panelFor(document, host).querySelector('.command-note'), null);
    }
    assert.deepEqual(codes(panelFor(document, 'vscode')), [canonical]);
  } finally { window.close(); }
});

test('indented comments attach to the next request and stay outside copyable inputs', () => {
  const canonical = '# First request\n  # More context\n    /squad init\n\n\t# A federation request\n\t/squad-federation promote';
  const { window, document } = openPage({ examples: [canonical] });
  try {
    for (const host of ['cli', 'app']) {
      const panel = panelFor(document, host);
      assert.deepEqual(codes(panel), ['init', 'promote']);
      assert.deepEqual([...panel.querySelectorAll('.command-note')].map(note => note.textContent), ['First request\nMore context', 'A federation request']);
    }
    assert.deepEqual(codes(panelFor(document, 'vscode')), [canonical]);
  } finally { window.close(); }
});

test('argument whitespace, tabs and escaped backslashes remain literal', () => {
  const input = '  request="C:\\\\work\\\\\nContinue here" mode=manual  ';
  const { window, document } = openPage({ examples: [`\t/squad ${input}`] });
  try {
    for (const host of ['cli', 'app']) assert.deepEqual(codes(panelFor(document, host)), [input]);
  } finally { window.close(); }
});

test('argument-free requests with trailing whitespace use defaults, never blank copy text', () => {
  const { window, document } = openPage({ examples: ['/squad   \n/squad-learn\t'] });
  try {
    assert.deepEqual(codes(panelFor(document, 'cli')), [locales.en.defaultRequests['/squad'], locales.en.defaultRequests['/squad-learn']]);
  } finally { window.close(); }
});

test('unknown, partial, mixed, unterminated and comment-only snippets remain wholly untouched', () => {
  const examples = [
    'gh issue comment 42 --body "/squad review"',
    '.github/skills/squad/squad-watch.workflow.yml',
    '/squad-doctor',
    '/squadron request="unknown"',
    '/squad-documentary request="unknown"',
    '/squad/init',
    '/squad request="unfinished',
    '/squad init\nnot a command',
    '/squad init\n/squad-unknown',
    '/squad init\n# Unattached trailing comment',
    '# Comment only',
    '/squad-document',
    '/squad-document  ',
    '/squad init\n/squad-document',
    ''
  ];
  const { window, document } = openPage({ examples });
  try {
    assert.equal(document.querySelector('.command-example'), null);
    assert.deepEqual(codes(document), examples);
  } finally { window.close(); }
});

test('inline code and explicit host references on ancestors, pre or code are not transformed', () => {
  const html = `<p><code>/squad init</code></p>
    <div data-host-reference><div class="code-block"><pre><code>/squad init</code></pre><button data-copy-target="original">Copy</button></div></div>
    <pre data-host-reference><code>/squad-federation promote</code></pre>
    <pre><code data-host-reference>/squad-governance-report</code></pre>`;
  const { window, document } = openPage({ html, scripts: false });
  try {
    const before = document.querySelector('main').outerHTML;
    window.eval(script);
    assert.equal(document.querySelector('main').outerHTML, before);
    assert.equal(document.querySelector('.command-example'), null);
  } finally { window.close(); }
});

test('manual guides are tabbed without rewriting host-specific instructions or nesting selectors', () => {
  const { window, document } = openPage({ html: manualGuide, examples: ['/squad init'], query: '?host=app' });
  try {
    assert.equal(document.querySelectorAll('.host-guide').length, 2);
    assert.equal(document.querySelector('.host-guide .host-guide'), null);
    assert.equal(document.querySelector('#install-cli pre code').textContent, '/squad init');
    assertSelected(document, 'app');
    document.querySelector('.installation-guide [role="tab"]').click();
    assertSelected(document, 'cli');
  } finally { window.close(); }
});

test('without scripts all manual panels and the canonical examples remain visible', () => {
  const { window, document } = openPage({ html: manualGuide, examples: ['/squad init'], scripts: false });
  try {
    assert.equal(document.querySelector('[role="tab"]'), null);
    for (const panel of document.querySelectorAll('.host-guide > [data-host]')) {
      assert.equal(panel.hidden, false);
      assert.ok(panel.querySelector('p'));
    }
    assert.deepEqual(codes(document), ['/squad init', '/squad init']);
  } finally { window.close(); }
});

test('tabs synchronize manual and generated instances with keyboard focus and roving tabindex', () => {
  const { window, document } = openPage({
    html: manualGuide, examples: ['/squad init', '/squad-learn'],
    query: '?host=cli&keep=value#section'
  });
  try {
    const tabs = tabsFor(document.querySelector('.command-example'));
    tabs[0].focus();
    for (const [key, expected] of [['ArrowLeft', 2], ['Home', 0], ['End', 2], ['ArrowRight', 0], ['ArrowRight', 1]]) {
      const event = new window.KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
      document.activeElement.dispatchEvent(event);
      assert.equal(event.defaultPrevented, true);
      assert.equal(document.activeElement, tabs[expected]);
      assertSelected(document, hosts[expected]);
      assert.equal(window.localStorage.getItem('hve-docs-host'), hosts[expected]);
    }
    assert.equal(window.location.search, '?host=app&keep=value');
    assert.equal(window.location.hash, '#section');
    const unrelated = new window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true });
    document.activeElement.dispatchEvent(unrelated);
    assert.equal(unrelated.defaultPrevented, false);
    assert.equal(document.activeElement, tabs[1]);
    assertSelected(document, 'app');
    const lastTabs = tabsFor([...document.querySelectorAll('.command-example')].at(-1));
    lastTabs[2].focus();
    lastTabs[2].click();
    assert.equal(document.activeElement, lastTabs[2]);
    assertSelected(document, 'vscode');
  } finally { window.close(); }
});

test('selection preserves the clicked tablist viewport position, not the first guide position', () => {
  const { window, document, scrolls } = openPage({ examples: ['/squad init', '/squad-learn'], query: '?host=cli' });
  try {
    assert.deepEqual(scrolls, [], 'initial selection must not scroll');
    const lists = [...document.querySelectorAll('[role="tablist"]')];
    lists[0].getBoundingClientRect = () => { throw new Error('Wrong scroll anchor'); };
    const positions = [400, 130, 130, 210, 210, 210];
    lists[1].getBoundingClientRect = () => ({ top: positions.shift() });
    const tabs = tabsFor(lists[1].parentElement);
    tabs[1].click();
    tabs[1].dispatchEvent(new window.KeyboardEvent('keydown', { key: 'End', bubbles: true }));
    tabs[2].click();
    assert.deepEqual(scrolls, [{ top: -270, behavior: 'instant' }, { top: 80, behavior: 'instant' }]);
    assertSelected(document, 'vscode');
  } finally { window.close(); }
});

for (const [query, stored, expected] of [
  ['', undefined, 'vscode'],
  ['', 'app', 'app'],
  ['', 'not-a-host', 'vscode'],
  ['?host=cli', 'app', 'cli'],
  ['?host=app', 'not-a-host', 'app'],
  ['?host=unknown', 'app', 'vscode'],
  ['?host=', 'cli', 'cli']
]) {
  test(`host preference query=${JSON.stringify(query)} stored=${JSON.stringify(stored)} selects ${expected}`, () => {
    const { window, document } = openPage({ query, stored, html: manualGuide, examples: ['/squad init'] });
    try {
      assertSelected(document, expected);
      assert.equal(window.localStorage.getItem('hve-docs-host'), expected);
      const url = new URL(window.location.href);
      assert.equal(url.searchParams.get('host'), query ? expected : null);
    } finally { window.close(); }
  });
}

test('blocked storage is tolerated and host queries are not added when absent', () => {
  const { window, document } = openPage({ examples: ['/squad init'], query: '?keep=yes#section', blockedStorage: true });
  try {
    assertSelected(document, 'vscode');
    document.querySelector('[role="tab"]').click();
    assertSelected(document, 'cli');
    assert.equal(window.location.search, '?keep=yes');
    assert.equal(window.location.hash, '#section');
  } finally { window.close(); }
});

test('existing history state is preserved while an explicit host query is updated', () => {
  const { window, document, run } = openPage({ examples: ['/squad init'], query: '?host=app', scripts: false });
  try {
    window.history.replaceState({ page: 'usage' }, '');
    run();
    document.querySelector('[role="tab"]').click();
    assert.equal(window.history.state.page, 'usage');
    assert.equal(window.location.search, '?host=cli');
  } finally { window.close(); }
});

test('build-time wrappers and stale copy targets are removed and all generated IDs are unique', () => {
  const html = `<p id="host-tab-0-cli">Existing anchor</p><p id="host-panel-0-app">Another anchor</p>
    <div class="code-block" id="old-wrapper"><button id="old-button" data-copy-target="old-code">Copy</button>
      <pre id="old-pre" class="source"><code id="old-code" class="language-text"><span id="old-token">/squad init</span></code><button data-copy-target="old-code">Copy</button></pre>
    </div>
    <div class="code-block" id="unchanged-wrapper"><pre><code id="shell-code">npm test</code></pre><button data-copy-target="shell-code">Copy</button></div>`;
  const { window, document, run, ready } = openPage({ html, examples: ['/squad-learn'], scripts: false });
  try {
    const unchanged = document.getElementById('unchanged-wrapper').outerHTML;
    run();
    assert.deepEqual(ready, [{ examples: 2, tabs: 6, pre: 7 }]);
    assert.equal(document.querySelector('.code-block .host-guide'), null);
    assert.equal(document.querySelector('.command-example .code-block'), null);
    assert.equal(document.querySelector('.command-example pre button'), null);
    assert.equal(document.querySelector('.command-example [data-copy-target]'), null);
    assert.equal(document.getElementById('unchanged-wrapper').outerHTML, unchanged);
    for (const id of ['old-wrapper', 'old-pre', 'old-code', 'old-button', 'old-token']) {
      assert.equal(document.getElementById(id), null);
    }
    assert.equal(panelFor(document, 'vscode').querySelector('pre').className, 'source');
    assert.equal(panelFor(document, 'vscode').querySelector('code').className, 'language-text');
    assert.deepEqual(codes(panelFor(document, 'vscode')), ['/squad init']);
    const ids = [...document.querySelectorAll('[id]')].map(element => element.id);
    assert.equal(new Set(ids).size, ids.length);
    for (const code of document.querySelectorAll('.command-example pre > code')) {
      assert.equal(code.id, '', 'shared site.js owns fresh copy IDs after transformation');
    }
    assertSelected(document, 'vscode');
  } finally { window.close(); }
});

test('the content-ready event is emitted even when there are no convertible examples', () => {
  const { window, ready } = openPage({ examples: ['npm test'] });
  try { assert.deepEqual(ready, [{ examples: 0, tabs: 0, pre: 1 }]); }
  finally { window.close(); }
});

test('missing language, configuration or required translations fails before mutating content', () => {
  const incomplete = structuredClone(locales);
  delete incomplete.fr.instructions.app;
  const badTemplate = structuredClone(locales);
  badTemplate.en.instructions.cli = 'Select an agent.';
  const scenarios = [
    [{ config: null }, /#site-ui/],
    [{ config: '{broken' }, /JSON/],
    [{ lang: '' }, /html.lang=""/],
    [{ lang: 'de' }, /html.lang="de"/],
    [{ lang: 'fr-CA' }, /html.lang="fr-CA"/],
    [{ config: { host: { en: locales.en } }, lang: 'fr' }, /html.lang="fr"/],
    [{ config: { host: incomplete }, lang: 'fr' }, /instructions.app/],
    [{ config: { host: badTemplate } }, /requires one \{agent\}/]
  ];
  for (const [options, error] of scenarios) {
    const { window, document, ready, run } = openPage({ ...options, html: manualGuide, examples: ['/squad init'], scripts: false });
    try {
      const before = document.querySelector('main').outerHTML;
      assert.throws(run, error);
      assert.equal(document.querySelector('main').outerHTML, before);
      assert.deepEqual(ready, []);
    } finally { window.close(); }
  }
});

test('new locales are selected strictly by html.lang without changing the host script', () => {
  const extra = structuredClone(locales.en);
  extra.tablistLabel = 'Entorno Copilot';
  extra.instructions.cli = 'Selecciona {agent} y envía:';
  extra.defaultRequests['/squad'] = 'Inicializa el equipo.';
  const { window, document } = openPage({ lang: 'es', examples: ['/squad'], config: { host: { ...locales, es: extra } } });
  try {
    assert.equal(document.querySelector('[role="tablist"]').getAttribute('aria-label'), extra.tablistLabel);
    assert.equal(panelFor(document, 'cli').querySelector('.command-instruction').textContent, 'Selecciona Squad Coordinator y envía:');
    assert.deepEqual(codes(panelFor(document, 'cli')), ['Inicializa el equipo.']);
  } finally { window.close(); }
});

test('request text, notes and locale strings are rendered as text rather than HTML', () => {
  const custom = structuredClone(locales.en);
  custom.instructions.app = '<img src=x onerror=alert(1)> {agent} <em>send</em>';
  custom.agents['/squad'] = '<script>alert(1)</script>';
  const input = 'request="<img src=x onerror=alert(1)>"';
  const canonical = `# <iframe src=x></iframe>\n/squad ${input}`;
  const { window, document } = openPage({ examples: [canonical], config: { host: { en: custom } } });
  try {
    const example = document.querySelector('.command-example');
    assert.equal(example.querySelector('img, iframe, script, em'), null);
    assert.deepEqual(codes(panelFor(document, 'app')), [input]);
    assert.equal(panelFor(document, 'app').querySelector('strong').textContent, custom.agents['/squad']);
    assert.equal(panelFor(document, 'app').querySelector('.command-note').textContent, '<iframe src=x></iframe>');
    assert.deepEqual(codes(panelFor(document, 'vscode')), [canonical]);
  } finally { window.close(); }
});
