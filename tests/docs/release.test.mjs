import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { load } from "cheerio";
import { JSDOM } from "jsdom";
import { buildPages, enhanceContent, headingIds, readLocales } from "../../scripts/docs-content.mjs";
import {
  addReleaseBadges,
  fetchPublishedReleases,
  populateReleaseInstalls,
  readReleaseInfo,
  resolveReleaseInfo,
} from "../../scripts/docs-release.mjs";

const economy = "20261005-routing-economy";
const fragment = (id, bump = "patch") => ({
  name: `${id}.md`, content: `---\nbump: ${bump}\ntype: Added\n---\n\n- A documented change.\n`,
});
const releaseRecord = (tag, prerelease = false, publishedAt = "2024-01-01T00:00:00Z") => ({
  tag_name: tag, draft: false, prerelease, published_at: publishedAt,
});
const published = (previewTag = "v2.5.0-pre", stableTag = "v2.4.7") => {
  const latest = releaseRecord(stableTag);
  return { latest, releases: previewTag ? [releaseRecord(previewTag, true), latest] : [latest] };
};
const pending = resolveReleaseInfo(published(), [fragment(economy, "minor")]);

test("published release tags are authoritative regardless of pending version bumps", () => {
  const metadata = published("v8.4.0-rc.2", "v8.3.6");
  for (const bumps of [["patch"], ["minor", "patch"], ["patch", "major", "minor"]]) {
    const release = resolveReleaseInfo(metadata, bumps.map((bump, i) => fragment(`change-${i}`, bump)));
    assert.equal(release.stableTag, metadata.latest.tag_name);
    assert.equal(release.previewTag, metadata.releases[0].tag_name);
    assert.equal(release.previewUrl, `https://github.com/Peter-N91/hve-squad/releases/tag/${metadata.releases[0].tag_name}`);
  }
});

test("GitHub's latest stable and the newest published non-draft pre-release are selected independently", () => {
  const metadata = published();
  metadata.releases = [
    releaseRecord("v2.5.0-pre", true, "2024-01-02T00:00:00Z"),
    releaseRecord("v1.9.9", false, "2024-01-05T00:00:00Z"),
    { ...releaseRecord("v9.0.0-pre", true, "2024-01-06T00:00:00Z"), draft: true },
    releaseRecord("v3.0.0-rc.1", true, "2024-01-04T00:00:00Z"),
  ];
  const release = resolveReleaseInfo(metadata, []);
  assert.equal(release.stableTag, metadata.latest.tag_name);
  assert.equal(release.previewTag, "v3.0.0-rc.1");
});

test("release fragment parsing accepts the quoted, case-insensitive and CRLF forms used by Release Prep", () => {
  const change = fragment("quoted");
  change.content = "---\r\nBump: 'MINOR'\r\nType: \"Changed\"\r\n---\r\n\r\n- Change.\r\n";
  assert.deepEqual(resolveReleaseInfo(published(), [change]).pendingChanges, ["quoted"]);
});

test("pre-release availability follows publication, not whether fragments are pending", () => {
  assert.equal(resolveReleaseInfo(published(), []).previewTag, published().releases[0].tag_name);
  const release = resolveReleaseInfo(published(null), [fragment(economy, "major")]);
  assert.equal(release.stableTag, published(null).latest.tag_name);
  assert.equal(release.previewTag, null);
  assert.equal(release.previewUrl, null);
  assert.deepEqual(release.pendingChanges, [economy]);
});

test("invalid release metadata fails instead of advertising a guessed version", () => {
  for (const latest of [
    null,
    { ...releaseRecord("v2.4.7"), tag_name: "latest" },
    { ...releaseRecord("v2.4.7"), draft: true },
    { ...releaseRecord("v2.4.7"), prerelease: true },
    { ...releaseRecord("v2.4.7"), published_at: null },
  ]) {
    assert.throws(() => resolveReleaseInfo({ ...published(), latest }, []), /published/);
  }
  assert.throws(() => resolveReleaseInfo({ ...published(), releases: null }, []), /release list/);
  assert.throws(() => resolveReleaseInfo({ ...published(), releases: [null] }, []), /release list entry/);
  assert.throws(() => resolveReleaseInfo({
    ...published(), releases: [{ ...releaseRecord("v2.5.0-pre", true), published_at: "invalid" }],
  }, []), /published pre-release/);
  for (const [content, message] of [
    ["bump: minor", /frontmatter/],
    ["---\nbump: tiny\ntype: Added\n---\n- Change.", /bump/],
    ["---\nbump: patch\ntype: Unknown\n---\n- Change.", /type/],
    ["---\nbump: patch\ntype: Added\n---\nNot a bullet.", /bullets/],
    ["---\nbump: patch\ntype: Added\n---\n- \n", /bullets/],
  ]) {
    assert.throws(() => resolveReleaseInfo(published(), [{ name: "invalid.md", content }]), message);
  }
});

test("published snapshots override the local manifest and support pending or consumed fragment directories", () => {
  const directory = mkdtempSync(join(tmpdir(), "hve-docs-release-"));
  try {
    writeFileSync(join(directory, "apm.yml"), "version: 99.0.0\n");
    assert.throws(() => readReleaseInfo(directory), /Missing published release snapshot/);
    const snapshot = join(directory, ".docs-releases.json");
    writeFileSync(snapshot, JSON.stringify(published(null)));
    assert.equal(readReleaseInfo(directory).stableTag, published(null).latest.tag_name);
    assert.equal(readReleaseInfo(directory).previewTag, null);
    const fragments = join(directory, ".changes", "unreleased");
    mkdirSync(fragments, { recursive: true });
    writeFileSync(join(fragments, "README.md"), "Not a fragment.");
    writeFileSync(join(fragments, "notes.txt"), "Not a fragment.");
    mkdirSync(join(fragments, "nested.md"));
    writeFileSync(join(fragments, `${economy}.md`), fragment(economy, "minor").content);
    assert.equal(readReleaseInfo(directory).previewTag, null);
    assert.deepEqual(readReleaseInfo(directory).pendingChanges, [economy]);
    writeFileSync(snapshot, JSON.stringify(published()));
    assert.equal(readReleaseInfo(directory).previewTag, published().releases[0].tag_name);
    rmSync(join(fragments, `${economy}.md`));
    writeFileSync(snapshot, JSON.stringify(published(null, "v3.0.0")));
    assert.equal(readReleaseInfo(directory).stableTag, "v3.0.0");
    assert.equal(readReleaseInfo(directory).previewTag, null);
    assert.deepEqual(readReleaseInfo(directory).pendingChanges, []);
  } finally {
    rmSync(directory, { recursive: true });
  }
});

test("published metadata fetches GitHub's latest endpoint and paginates the release list", async () => {
  const metadata = published();
  const urls = [];
  const response = body => new Response(JSON.stringify(body), { status: 200 });
  const fetched = await fetchPublishedReleases(async (url, options) => {
    urls.push(url);
    assert.equal(options.headers.Accept, "application/vnd.github+json");
    assert(options.signal instanceof AbortSignal);
    if (url.endsWith("/latest")) return response({ ...metadata.latest, body: "Release notes are not cached." });
    if (url.endsWith("page=1")) return response(Array.from({ length: 100 }, () => metadata.latest));
    assert(url.endsWith("page=2"));
    return response([metadata.releases[0]]);
  });
  assert.equal(urls.length, 3);
  assert.equal(fetched.releases.length, 101);
  assert.equal(fetched.latest.tag_name, metadata.latest.tag_name);
  assert.equal(Object.hasOwn(fetched.latest, "body"), false);
  assert.equal(resolveReleaseInfo(fetched, []).previewTag, metadata.releases[0].tag_name);
});

test("API failures and malformed responses cannot masquerade as an absent pre-release", async () => {
  for (const status of [403, 404, 500]) {
    await assert.rejects(fetchPublishedReleases(async () => new Response("", { status })), /GitHub release lookup failed/);
  }
  await assert.rejects(fetchPublishedReleases(async url => new Response(JSON.stringify(
    url.endsWith("/latest") ? published().latest : { unexpected: "not a release list" },
  ), { status: 200 })), /Invalid GitHub release list/);
});

test("unmarked stable sections are never inferred as pre-release content", () => {
  const $ = load(`<main><h2 id="stable">Stable section</h2><p>Edited stable copy.</p></main>`);
  addReleaseBadges($, pending, readLocales().en.ui.release);
  assert.equal($(".prerelease-badge").length, 0);
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
      assert.equal($(element).text(), `${ui.previewOnly} ${pending.previewTag}`);
      assert($(element).attr("title").includes(pending.stableTag));
      assert.equal($(element).find("svg").attr("aria-hidden"), "true");
    });
  });

  test(`${language}: exact preview and stable install commands are rendered without browser JavaScript`, () => {
    const $ = load('<main><div data-release-install="preview"></div><div data-release-install="stable"></div></main>');
    populateReleaseInstalls($, pending, ui);
    assert.equal($('[data-release-install="preview"] pre code').text(), `apm install "Peter-N91/hve-squad#${pending.previewTag}" --target copilot`);
    assert.equal($('[data-release-install="stable"] pre code').text(), `apm install "Peter-N91/hve-squad#${pending.stableTag}" --target copilot`);
    assert.equal($('[data-release-install="preview"] a').attr("href"), pending.previewUrl);
  });

  test(`${language}: a shipped feature stays unbadged when the next, unrelated preview opens`, () => {
    const $ = load(`<main><p data-release-change="${economy}">Economy</p><div data-release-install="preview"></div></main>`);
    const stable = resolveReleaseInfo(published(null), []);
    addReleaseBadges($, stable, ui);
    populateReleaseInstalls($, stable, ui);
    assert.equal($(".prerelease-badge, pre").length, 0);
    assert.equal($("[data-release-install]").text(), ui.noPreview);
    const nextPreview = resolveReleaseInfo(published(), [fragment("unrelated")]);
    addReleaseBadges($, nextPreview, ui);
    assert.equal($(".prerelease-badge").length, 0);
  });

  test(`${language}: pending changes do not advertise a preview that has not been published`, () => {
    const $ = load(`<main><h2 data-release-change="${economy}">Feature</h2><div data-release-install="preview"></div></main>`);
    const release = resolveReleaseInfo(published(null), [fragment(economy, "major")]);
    addReleaseBadges($, release, ui);
    populateReleaseInstalls($, release, ui);
    assert.equal($(".prerelease-badge, pre").length, 0);
    assert.equal($("[data-release-install]").text(), ui.noPreview);
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

test("both languages track published preview renames, hotfixes and consumed feature fragments", () => {
  for (const release of [
    pending,
    resolveReleaseInfo(published("v3.0.0-pre"), [fragment(economy, "minor"), fragment("breaking", "major")]),
    resolveReleaseInfo(published("v2.5.0-pre", "v2.4.8"), [fragment(economy, "minor")]),
    resolveReleaseInfo(published(null, "v2.5.0"), []),
  ]) {
    const pages = buildPages(undefined, release);
    for (const language of ["en", "fr"]) {
      const usage = pages.find(page => page.language === language && page.slug === "usage");
      const $ = load(usage.content);
      assert.equal($("#routing-economy .prerelease-badge").length, release.previewTag ? 1 : 0);
      if (release.previewTag) {
        assert($("#routing-economy .prerelease-badge").text().includes(release.previewTag));
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

test("only explicitly marked pending features receive pre-release badges", () => {
  const unbadgedPages = buildPages(undefined, resolveReleaseInfo(published(null), []));
  const markers = new Map(unbadgedPages.map(page => {
    const $ = load(page.content);
    return [page.outputPath, $("[data-release-change]").toArray().map(element => $(element).attr("data-release-change"))];
  }));
  const changes = [...new Set([...markers.values()].flat())];
  assert(changes.length > 0);
  for (const offset of [0, 1]) {
    const fragments = changes.filter((id, index) => index % 2 === offset).map(id => fragment(id));
    const release = resolveReleaseInfo(published(), fragments);
    for (const page of buildPages(undefined, release)) {
      const $ = load(page.content);
      const expected = markers.get(page.outputPath).filter(id => release.pendingChanges.includes(id)).length;
      assert.equal($(".prerelease-badge").length, expected, page.outputPath);
      $("h1, h2, h3, h4").each((index, element) => {
        const marked = release.pendingChanges.includes($(element).attr("data-release-change"));
        assert.equal($(element).children(".prerelease-badge").length, marked ? 1 : 0, page.outputPath);
      });
    }
  }
});

for (const [state, metadata, fragments] of [
  ["after Release Prep consumes the batch", published(null), []],
  ["when a later unrelated preview opens", published(), [fragment("unrelated")]],
]) {
  test(`released documentation stays unbadged ${state}`, () => {
    const release = resolveReleaseInfo(metadata, fragments);
    for (const page of buildPages(undefined, release)) {
      const $ = load(page.content);
      assert.equal($(".prerelease-badge").length, 0, page.outputPath);
      assert.equal(load(page.previewBadge)(".prerelease-badge").length, release.previewTag ? 1 : 0, page.outputPath);
      $("[data-release-install]").each((index, element) => {
        const tag = $(element).attr("data-release-install") === "preview" ? release.previewTag : release.stableTag;
        assert.deepEqual($(element).find("pre code").toArray().map(code => $(code).text()),
          tag ? [`apm install "Peter-N91/hve-squad#${tag}" --target copilot`] : [], page.outputPath);
      });
    }
  });
}

test("explicit release markers stay aligned across translations", () => {
  const pages = buildPages(undefined, resolveReleaseInfo(published(null), []));
  for (const english of pages.filter(page => page.language === "en")) {
    const translated = pages.find(page => page.language === "fr" && page.slug === english.slug);
    const markers = page => {
      const $ = load(page.content);
      return $("[data-release-change]").toArray().map(element => $(element).attr("data-release-change"));
    };
    assert.deepEqual(markers(translated), markers(english), english.slug);
  }
});

test("fragment-only merges rebuild the published version notice", () => {
  const workflow = readFileSync(new URL("../../.github/workflows/docs.yml", import.meta.url), "utf8");
  assert.equal(workflow.match(/- '\.changes\/unreleased\/\*\*'/g)?.length, 2);
  assert.doesNotMatch(workflow, /fetch-depth:\s*0/);
});

test("release lifecycle refreshes Pages from the default branch, including GITHUB_TOKEN publishers", () => {
  const workflow = readFileSync(new URL("../../.github/workflows/docs.yml", import.meta.url), "utf8");
  assert.match(workflow, /release:\s*\n\s+types: \[published, edited, deleted\]/);
  assert.doesNotMatch(workflow, /workflow_run:/);
  assert.match(workflow, /ref:.*github\.event_name == 'release' && github\.event\.repository\.default_branch/);
  assert.equal(workflow.match(/if: \(github\.ref == 'refs\/heads\/main' \|\| github\.event_name == 'release'\)/g)?.length, 2);
  for (const name of ["release", "release-prep", "preview"]) {
    const publisher = readFileSync(new URL(`../../.github/workflows/${name}.yml`, import.meta.url), "utf8");
    assert.match(publisher, /actions: write/);
    assert.match(publisher, /name: Refresh published documentation\s*\n\s*if: always\(\)/);
    assert.match(publisher, /run: gh workflow run docs\.yml --repo "\$GITHUB_REPOSITORY" --ref main/);
  }
  const prep = readFileSync(new URL("../../.github/workflows/release-prep.yml", import.meta.url), "utf8");
  assert.match(prep, /if: always\(\).*has_changes == 'true'.*inputs\.dry_run != true.*inputs\.ref == 'main'/);
  const scripts = JSON.parse(readFileSync(new URL("../../package.json", import.meta.url), "utf8")).scripts;
  assert(scripts["docs:build"].startsWith("node scripts/docs-release.mjs --refresh && "));
});
