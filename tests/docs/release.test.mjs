import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { load } from "cheerio";
import { JSDOM } from "jsdom";
import { buildPages, enhanceContent, headingIds, readLocales } from "../../scripts/docs-content.mjs";
import {
  addReleaseBadges,
  annotateReleaseSource,
  createAutomaticReleaseAnnotator,
  populateReleaseInstalls,
  readPendingChangeCommits,
  readReleaseInfo,
  resolveReleaseInfo,
} from "../../scripts/docs-release.mjs";

const economy = "20261005-routing-economy";
const fragment = (id, bump = "patch") => ({
  name: `${id}.md`, content: `---\nbump: ${bump}\ntype: Added\n---\n\n- A documented change.\n`,
});
const pending = resolveReleaseInfo("version: 0.18.1\n", [fragment(economy, "minor")]);

test("the highest pending bump determines the rolling tag, not the stable manifest version", () => {
  for (const [bumps, tag] of [
    [["patch"], "v0.18.2-pre"],
    [["minor", "patch"], "v0.19.0-pre"],
    [["patch", "major", "minor"], "v1.0.0-pre"],
  ]) {
    const release = resolveReleaseInfo("version: 0.18.1\n", bumps.map((bump, i) => fragment(`change-${i}`, bump)));
    assert.equal(release.stableTag, "v0.18.1");
    assert.equal(release.previewTag, tag);
    assert.equal(release.previewUrl, `https://github.com/Peter-N91/hve-squad/releases/tag/${tag}`);
  }
});

test("release fragment parsing accepts the quoted, case-insensitive and CRLF forms used by Release Prep", () => {
  const change = fragment("quoted");
  change.content = "---\r\nBump: 'MINOR'\r\nType: \"Changed\"\r\n---\r\n\r\n- Change.\r\n";
  assert.equal(resolveReleaseInfo("version: 1.8.9\r\n", [change]).previewTag, "v1.9.0-pre");
});

test("an empty pending batch has no pre-release, even after a version override", () => {
  const release = resolveReleaseInfo("version: 0.18.2\n", []);
  assert.equal(release.stableTag, "v0.18.2");
  assert.equal(release.previewTag, null);
  assert.equal(release.previewUrl, null);
  assert.deepEqual(release.pendingChanges, []);
});

test("invalid release metadata fails instead of advertising a guessed version", () => {
  for (const manifest of ["", "version: latest\n", "version: 0.18.1-pre\n"]) {
    assert.throws(() => resolveReleaseInfo(manifest, []), /APM version/);
  }
  for (const [content, message] of [
    ["bump: minor", /frontmatter/],
    ["---\nbump: tiny\ntype: Added\n---\n- Change.", /bump/],
    ["---\nbump: patch\ntype: Unknown\n---\n- Change.", /type/],
    ["---\nbump: patch\ntype: Added\n---\nNot a bullet.", /bullets/],
    ["---\nbump: patch\ntype: Added\n---\n- \n", /bullets/],
  ]) {
    assert.throws(() => resolveReleaseInfo("version: 0.18.1", [{ name: "invalid.md", content }]), message);
  }
});

test("metadata reads only pending markdown files and supports a consumed fragment directory", () => {
  const directory = mkdtempSync(join(tmpdir(), "hve-docs-release-"));
  try {
    writeFileSync(join(directory, "apm.yml"), "version: 0.18.1\n");
    assert.equal(readReleaseInfo(directory).previewTag, null);
    const fragments = join(directory, ".changes", "unreleased");
    mkdirSync(fragments, { recursive: true });
    writeFileSync(join(fragments, "README.md"), "Not a fragment.");
    writeFileSync(join(fragments, "notes.txt"), "Not a fragment.");
    mkdirSync(join(fragments, "nested.md"));
    writeFileSync(join(fragments, `${economy}.md`), fragment(economy, "minor").content);
    assert.equal(readReleaseInfo(directory).previewTag, "v0.19.0-pre");
    assert.deepEqual(readReleaseInfo(directory).pendingChanges, [economy]);
  } finally {
    rmSync(directory, { recursive: true });
  }
});

test("merge-added fragments and pages retain their release provenance", () => {
  const directory = mkdtempSync(join(tmpdir(), "hve-docs-merge-"));
  const git = (...args) => execFileSync("git", [
    "-c", "user.name=Test", "-c", "user.email=test@example.invalid", ...args,
  ], { cwd: directory, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  try {
    git("init", "-q", "-b", "main");
    writeFileSync(join(directory, "apm.yml"), "version: 0.18.1\n");
    git("add", ".");
    git("commit", "-qm", "Base");
    git("checkout", "-qb", "feature");
    writeFileSync(join(directory, "feature.txt"), "Feature\n");
    git("add", ".");
    git("commit", "-qm", "Feature");
    git("checkout", "-q", "main");
    git("merge", "--no-ff", "--no-commit", "feature");
    const fragments = join(directory, ".changes", "unreleased");
    mkdirSync(fragments, { recursive: true });
    writeFileSync(join(fragments, "merge-added.md"), fragment("merge-added").content);
    const raw = "<header class=\"hero\"><h1>New guide</h1></header>\n<main><h2>Details</h2></main>\n";
    writeFileSync(join(directory, "guide.html"), raw);
    git("add", ".");
    git("commit", "-qm", "Merge with release documentation");
    const commit = git("rev-parse", "HEAD");
    const release = readReleaseInfo(directory);
    assert.deepEqual([...readPendingChangeCommits(release, directory)], [commit]);
    const annotated = load(createAutomaticReleaseAnnotator(release, directory)("guide.html", raw));
    assert.equal(annotated("h1[data-release-auto]").length, 1);
    assert.equal(annotated("h2[data-release-auto]").length, 0);
  } finally {
    rmSync(directory, { recursive: true });
  }
});

test("automatic annotations group pending content under the nearest safe section heading", () => {
  const lines = [
    "<body>",
    "<nav><a href=\"usage.html\">Changed navigation</a></nav>",
    "<header class=\"hero\">",
    "  <h1>Guide</h1>",
    "</header>",
    "<main>",
    "  <h2 id=\"stable\">Stable section</h2>",
    "  <p>Changed stable copy.</p>",
    "  <h2 id=\"new\">New feature</h2>",
    "  <p>New feature detail.</p>",
    "  <a href=\"elsewhere.html\"><h3 id=\"card\">Changed card</h3></a>",
    "</main>",
    "</body>",
  ];
  const line = text => lines.indexOf(text) + 1;
  const annotated = annotateReleaseSource(lines.join("\n"), new Set([
    line("<nav><a href=\"usage.html\">Changed navigation</a></nav>"),
    line("  <p>Changed stable copy.</p>"),
    line("  <h2 id=\"new\">New feature</h2>"),
    line("  <p>New feature detail.</p>"),
    line("  <a href=\"elsewhere.html\"><h3 id=\"card\">Changed card</h3></a>"),
  ]));
  const $ = load(annotated);
  assert.equal($("#stable").attr("data-release-auto"), "");
  assert.equal($("#new").attr("data-release-auto"), "");
  assert.equal($("h1, #card").filter("[data-release-auto]").length, 0);
});

test("a documentation page added by a pending change gets one page-level annotation", () => {
  const raw = [
    "<body>",
    "<header class=\"hero\"><h1>New guide</h1></header>",
    "<main><h2>First section</h2><p>New content.</p><h2>Second section</h2></main>",
    "</body>",
  ].join("\n");
  const $ = load(annotateReleaseSource(raw, new Set([2, 3]), true));
  assert.equal($("h1[data-release-auto]").length, 1);
  assert.equal($("h2[data-release-auto]").length, 0);
});

for (const language of ["en", "fr"]) {
  const ui = readLocales()[language].ui.release;

  test(`${language}: only pending features get a versioned, keyboard-accessible installation link`, () => {
    const $ = load(`<main><h2 id="kept" data-release-change="${economy}">Models</h2><p>Stable <code>ranked</code>; preview <code data-release-change="${economy}">economy</code>.</p><p data-release-change="already-shipped">Stable behavior.</p><pre data-release-change="${economy}"><code>request="test" routing=economy</code></pre></main>`);
    const ids = headingIds($);
    const { toc } = enhanceContent($, ids, readLocales()[language].ui, language === "en" ? "" : "../");
    addReleaseBadges($, pending, ui);
    assert.deepEqual(toc.map(heading => heading.text), ["Models"]);
    assert.equal($("h2").attr("id"), "kept");
    assert.equal($(".prerelease-badge").length, 3);
    assert.equal($('[data-release-change="already-shipped"] .prerelease-badge').length, 0);
    assert.equal($("code .prerelease-badge, pre .prerelease-badge, a a").length, 0);
    assert.equal($("pre code").text(), 'request="test" routing=economy');
    $(".prerelease-badge").each((index, element) => {
      assert.equal(element.tagName, "a");
      assert.equal($(element).attr("href"), "getting-started.html#testing-the-pre-release");
      assert.equal($(element).text(), `${ui.previewOnly} v0.19.0-pre`);
      assert($(element).attr("title").includes("v0.18.1"));
      assert.equal($(element).find("svg").attr("aria-hidden"), "true");
    });
  });

  test(`${language}: exact preview and stable install commands are rendered without browser JavaScript`, () => {
    const $ = load('<main><div data-release-install="preview"></div><div data-release-install="stable"></div></main>');
    populateReleaseInstalls($, pending, ui);
    assert.equal($('[data-release-install="preview"] pre code').text(), 'apm install "Peter-N91/hve-squad#v0.19.0-pre" --target copilot');
    assert.equal($('[data-release-install="stable"] pre code').text(), 'apm install "Peter-N91/hve-squad#v0.18.1" --target copilot');
    assert.equal($('[data-release-install="preview"] a').attr("href"), pending.previewUrl);
  });

  test(`${language}: a shipped feature stays unbadged when the next, unrelated preview opens`, () => {
    const $ = load(`<main><p data-release-change="${economy}">Economy</p><div data-release-install="preview"></div></main>`);
    const stable = resolveReleaseInfo("version: 0.18.2\n", []);
    addReleaseBadges($, stable, ui);
    populateReleaseInstalls($, stable, ui);
    assert.equal($(".prerelease-badge, pre").length, 0);
    assert.equal($("[data-release-install]").text(), ui.noPreview);
    const nextPreview = resolveReleaseInfo("version: 0.18.2\n", [fragment("unrelated")]);
    addReleaseBadges($, nextPreview, ui);
    assert.equal($(".prerelease-badge").length, 0);
  });
}

test("invalid annotation locations and installation channels are rejected", () => {
  const ui = readLocales().en.ui.release;
  for (const html of [
    '<p data-release-change="../invalid">Feature</p>',
    `<a href="usage.html"><span data-release-change="${economy}">Feature</span></a>`,
    `<pre><code data-release-change="${economy}">example</code></pre>`,
  ]) {
    assert.throws(() => addReleaseBadges(load(`<main>${html}</main>`), pending, ui), /data-release-change/);
  }
  assert.throws(() => populateReleaseInstalls(load('<main><div data-release-install="unknown"></div></main>'), pending, ui), /channel/);
});

test("a code example's badge survives host-tab enhancement and stays outside copyable requests", () => {
  const $ = load(`<main><pre data-release-change="${economy}"><code>/squad request="test" routing=economy</code></pre></main>`);
  enhanceContent($, [], readLocales().en.ui, "");
  addReleaseBadges($, pending, readLocales().en.ui.release);
  const hosts = JSON.parse(readFileSync(new URL("../../site/host-locales.json", import.meta.url), "utf8"));
  const dom = new JSDOM(`<html lang="en"><body>${$("main").toString()}<script type="application/json" id="site-ui">${JSON.stringify({ host: hosts })}</script></body></html>`, {
    url: "https://docs.example/hve-squad/usage.html", runScripts: "outside-only",
  });
  try {
    dom.window.eval(readFileSync(new URL("../../site/assets/hosts.js", import.meta.url), "utf8"));
    const document = dom.window.document;
    assert.equal(document.querySelectorAll(".prerelease-badge").length, 1);
    assert(document.querySelector(".prerelease-badge").nextElementSibling.classList.contains("command-example"));
    for (const tab of document.querySelectorAll('[role="tab"]')) {
      tab.click();
      assert.equal(document.querySelector('[role="tabpanel"]:not([hidden]) pre code').textContent, 'request="test" routing=economy');
      assert.equal(document.querySelector(".command-example .prerelease-badge"), null);
    }
  } finally {
    dom.window.close();
  }
});

for (const hiddenPanel of [false, true]) {
  test(`the release guide anchor is repositioned after host enhancement (hidden panel: ${hiddenPanel})`, () => {
    const target = '<h2 id="testing-the-pre-release">Install and test the pre-release</h2>';
    const content = hiddenPanel
      ? `<div class="host-guide"><button role="tab" aria-controls="preview-panel"></button><section id="preview-panel" data-host="vscode" hidden>${target}</section></div>`
      : target;
    const dom = new JSDOM(`<html data-theme-preference="system"><body><header class="site-header"></header><select class="theme-select"></select><select class="locale-select"></select><details class="mobile-navigation"><summary>Menu</summary></details><main class="doc-content">${content}</main><button class="search-trigger"></button><dialog class="search-dialog"><p class="search-state"></p><button class="search-close"></button></dialog><p id="site-status"></p><script type="application/json" id="site-ui">${JSON.stringify(readLocales().en.ui)}</script></body></html>`, {
      url: "https://docs.example/hve-squad/getting-started.html#testing-the-pre-release", runScripts: "outside-only",
    });
    try {
      const { window } = dom;
      const { document } = window;
      window.matchMedia = () => ({ addEventListener() {} });
      const scrolls = [];
      document.getElementById("testing-the-pre-release").scrollIntoView = () => scrolls.push("guide");
      document.querySelector('[role="tab"]')?.addEventListener("click", () => { document.getElementById("preview-panel").hidden = false; });
      window.eval(readFileSync(new URL("../../site/assets/site.js", import.meta.url), "utf8"));
      assert.deepEqual(scrolls, ["guide"]);
      if (hiddenPanel) assert.equal(document.getElementById("preview-panel").hidden, false);
    } finally {
      dom.window.close();
    }
  });
}

test("both languages track preview renames, hotfixes and consumed feature fragments", () => {
  for (const release of [
    pending,
    resolveReleaseInfo("version: 0.18.1\n", [fragment(economy, "minor"), fragment("breaking", "major")]),
    resolveReleaseInfo("version: 0.18.2\n", [fragment(economy, "minor")]),
    resolveReleaseInfo("version: 0.18.2\n", []),
  ]) {
    const pages = buildPages(undefined, release);
    for (const language of ["en", "fr"]) {
      const usage = pages.find(page => page.language === language && page.slug === "usage");
      const $ = load(usage.content);
      assert.equal($("#model-selection-per-role .prerelease-badge").length, release.previewTag ? 1 : 0);
      if (release.previewTag) {
        assert($("#model-selection-per-role .prerelease-badge").text().includes(release.previewTag));
        assert($(".prerelease-badge").length > 0);
      } else {
        assert.equal($(".prerelease-badge").length, 0);
      }
      assert.equal(usage.release.stableTag, release.stableTag);
      const setup = load(pages.find(page => page.language === language && page.slug === "getting-started").content);
      assert.equal(setup("#testing-the-pre-release").length, 1);
      assert.equal(setup('[data-release-install="preview"] pre').length, release.previewTag ? 1 : 0);
      if (release.previewTag) {
        assert.equal(setup('[data-release-install="preview"] pre code').text(),
          `apm install "Peter-N91/hve-squad#${release.previewTag}" --target copilot`);
      }
    }
  }
});

test("all currently documented pending features receive automatic pre-release badges", () => {
  const release = readReleaseInfo();
  assert(release.previewTag);
  const pages = buildPages(undefined, release);
  for (const language of ["en", "fr"]) {
    const connector = load(pages.find(page => page.language === language && page.slug === "connector").content);
    const gettingStarted = load(pages.find(page => page.language === language && page.slug === "getting-started").content);
    const usage = load(pages.find(page => page.language === language && page.slug === "usage").content);
    assert.equal(connector("h1 .prerelease-badge").length, 1);
    assert.equal(gettingStarted("#chat-with-the-squad-coach .prerelease-badge").length, 1);
    assert.equal(gettingStarted("#testing-the-pre-release .prerelease-badge").length, 1);
    assert.equal(usage("#model-selection-per-role .prerelease-badge").length, 1);
  }
});

test("fragment-only merges rebuild the published version notice", () => {
  const workflow = readFileSync(new URL("../../.github/workflows/docs.yml", import.meta.url), "utf8");
  assert.equal(workflow.match(/- '\.changes\/unreleased\/\*\*'/g)?.length, 2);
  assert.match(workflow, /fetch-depth:\s*0/);
});
