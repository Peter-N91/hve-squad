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

function openPage(name, { query = '', stored = {}, blockedStorage = false, darkSystem = false, scripts = true } = {}) {
  const dom = new JSDOM(load(name), { url: `${origin}${name}${query}`, runScripts: 'outside-only' });
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
      } finally { dom.window.close(); }
    });

    test(`${relative}: one active host panel and accessible navigation`, () => {
      const dom = openPage(relative, { query: '?host=cli' });
      try {
        const document = dom.window.document;
        assertNoPartnerWorkshopLinks(document);
        assert.equal(document.querySelectorAll('[role="tab"]').length, 3);
        assert.equal(document.querySelectorAll('[role="tab"][aria-selected="true"]').length, 1);
        assert.equal(document.querySelectorAll('[role="tabpanel"]:not([hidden])').length, 1);
        assert.equal(document.querySelector('[role="tab"][aria-selected="true"]').textContent, 'Copilot CLI');
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
  }
}

test('host tabs support arrow keys, Home, End, focus and persistence', () => {
  const dom = openPage('getting-started.html', { query: '?host=cli' });
  try {
    const document = dom.window.document;
    const tabs = [...document.querySelectorAll('[role="tab"]')];
    tabs[0].focus();
    for (const [key, expected] of [['ArrowLeft', 2], ['Home', 0], ['End', 2], ['ArrowRight', 0], ['ArrowRight', 1]]) {
      document.activeElement.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
      assert.equal(document.activeElement, tabs[expected]);
      assert.equal(tabs[expected].getAttribute('aria-selected'), 'true');
      assert.equal(tabs[expected].tabIndex, 0);
    }
    assert.equal(dom.window.localStorage.getItem('hve-docs-host'), 'app');
    assert.equal(new URL(dom.window.location.href).searchParams.get('host'), 'app');
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
        assert.ok(panel.querySelector('pre code'));
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