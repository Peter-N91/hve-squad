import assert from "node:assert/strict";
import test from "node:test";
import { load } from "cheerio";
import { assembleContent, enhanceContent, headingIds, readLocales, pageOrder } from "../../scripts/docs-content.mjs";

test("every declared language has the complete navigation and UI contract", () => {
  const locales = readLocales();
  assert(locales.en && locales.fr);
  for (const locale of Object.values(locales)) {
    assert.equal(Object.keys(locale.pages).length, pageOrder.length);
    for (const value of Object.values(locale.ui)) assert(value);
  }
});

test("section anchors preserve existing IDs and disambiguate repeated headings", () => {
  const $ = load('<main><h2 id="kept">One</h2><h2>Déjà vu</h2><h2>Déjà vu</h2><h3 id="deja-vu">Nested</h3></main>');
  assert.deepEqual(headingIds($), ["kept", "deja-vu-2", "deja-vu-3", "deja-vu"]);
});

test("translated pages use their English section identity and preserve code", () => {
  const $ = load('<main><h1>Test</h1><h2>Préparation</h2><pre><code>const x = "&lt;value&gt;";\n</code></pre><table><thead><tr><th>Nom</th></tr></thead></table></main>');
  const ui = readLocales().fr.ui;
  const result = enhanceContent($, ["preparation"], ui, "../");
  assert.equal(result.toc[0].id, "preparation");
  assert.equal(result.toc[0].text, "Préparation");
  assert.equal($("pre code").text(), 'const x = "<value>";\n');
  assert.equal($(".copy-button").text(), "Copier");
  assert.equal($("th").attr("scope"), "col");
  assert.equal($(".table-scroll").attr("tabindex"), "0");
});

test("incomplete translations fail rather than silently dropping sections", () => {
  assert.throws(() => enhanceContent(load("<main><h2>Un</h2></main>"), ["one", "two"], readLocales().fr.ui, "../"), /preserve all section/);
});

test("linked card headings do not acquire nested anchors or clutter the contents", () => {
  const $ = load('<main><h2>Next steps</h2><a class="card" href="tools.html"><h3>Tools</h3><p>Reference.</p></a></main>');
  const result = enhanceContent($, ["next-steps", "tools"], readLocales().en.ui, "");
  assert.equal($("a.card a").length, 0);
  assert.equal($("a.card h3").attr("id"), "tools");
  assert.deepEqual(result.toc.map(item => item.id), ["next-steps"]);
});

test("labelled code and table containers are enhanced rather than nested", () => {
  const $ = load('<main><section id="setup"><h2>Setup</h2><div class="code-block"><div class="code-heading">Code example</div><pre><code>await RunAsync();</code></pre></div><div class="table-wrap"><table><tr><td>Value</td></tr></table></div></section></main>');
  const ids = headingIds($);
  enhanceContent($, ids, readLocales().en.ui, "");
  assert.equal($(".code-block").length, 1);
  assert.equal($(".code-heading .copy-button").length, 1);
  assert.equal($(".table-wrap.table-scroll").length, 1);
  assert.equal($("main > nav.toc").length, 0);
  assert.equal($("section").attr("id"), "setup");
  assert.notEqual($("h2").attr("id"), "setup");
});

test("the original external hero is included without discarding its headline or introduction", () => {
  const $ = load('<body><header class="hero"><h1>The Squad, installable.</h1><p>Original introduction.</p><div class="hero-logo"><img src="assets/logo.svg" alt="Three nodes"><span class="wordmark">old-wordmark</span></div></header><main><h2>Setup</h2><p>Instructions.</p></main></body>');
  assembleContent($);
  enhanceContent($, headingIds($), readLocales().en.ui, "../");
  assert.equal($("main h1").text(), "The Squad, installable.");
  assert.equal($("main [data-source-hero] p").text(), "Original introduction.");
  assert.equal($("main img").attr("src"), "../assets/logo.svg");
  assert.equal($("main img").attr("alt"), "Three nodes");
  assert.equal($("main .wordmark").text(), "HVE Squad");
  assert.equal($("main [data-source-body] p").text(), "Instructions.");
});
