import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { load } from "cheerio";
import { buildPages, diagramSource, readSource, repositoryRoot } from "./docs-content.mjs";
import { localizeDiagram } from "./diagram-locales.mjs";

const output = resolve(repositoryRoot, "_site");
const normalized = value => value.replace(/\s+/g, " ").trim();
const renderedDocuments = new Map();
const pages = buildPages();

for (const page of pages) {
  const target = resolve(output, page.outputPath);
  assert(existsSync(target), `Missing built page ${page.outputPath}; run npm run docs:build.`);
  const $ = load(readFileSync(target, "utf8"));
  renderedDocuments.set(target, $);
  assert.equal($("html").attr("lang"), page.language);
  assert.equal($("main").length, 1);
  assert.equal($("h1").length, 1, `${page.outputPath}: needs exactly one page heading`);
  assert.equal($("title").text(), page.title);
  assert.equal($('link[rel="alternate"][hreflang]').length, page.languages.length + 1);
  const ids = $("[id]").toArray().map(element => $(element).attr("id"));
  assert.equal(new Set(ids).size, ids.length, `${page.outputPath}: duplicate IDs`);

  const source = readSource(page.slug, page.language === "en" ? "" : page.outputPath.split("/")[0] + "/").$;
  const sourceBody = source("main").clone();
  const builtBody = $("[data-source-body]").clone();
  sourceBody.find(".mermaid").remove();
  builtBody.find(".diagram").remove();
  builtBody.find("[data-site-ui]").remove();
  assert.equal(normalized(builtBody.text()), normalized(sourceBody.text()), `${page.outputPath}: source prose changed`);
  const sourceHero = source("header.hero").clone();
  const builtHero = $("[data-source-hero]").clone();
  sourceHero.find(".hero-logo").remove();
  builtHero.find(".hero-logo, [data-site-ui]").remove();
  assert.equal(normalized(builtHero.text()), normalized(sourceHero.text()), `${page.outputPath}: hero introduction changed`);
  assert.equal(normalized($("[data-source-demo]").text()), normalized(source(".demo-bar").text()), `${page.outputPath}: demo selector changed`);
  assert.equal(normalized($(".footer-source").text()), normalized(source("footer").text()), `${page.outputPath}: footer disclaimer changed`);
  const code = doc => doc("main pre:not(.diagram-code)").toArray().map(element => doc(element).text());
  assert.deepEqual(code($), code(source), `${page.outputPath}: code samples changed`);
  const english = readSource(page.slug).$;
  const shape = doc => doc("body > header.hero, body > .demo-bar, main").find("*")
    .toArray().map(element => element.tagName);
  assert.deepEqual(shape(source), shape(english), `${page.outputPath}: translation omitted or reorganized content`);
  assert.deepEqual(code(source), code(english), `${page.outputPath}: translated code samples differ from English`);
  const inline = doc => doc("body > header.hero code, main code").toArray().map(element => doc(element).text());
  assert.deepEqual(inline(source), inline(english), `${page.outputPath}: technical identifiers changed`);
  const externalLinks = doc => doc("body > header.hero a[href], main a[href]").toArray()
    .map(element => doc(element).attr("href")).filter(href => /^https?:/.test(href));
  assert.deepEqual(externalLinks(source), externalLinks(english), `${page.outputPath}: external references changed`);
  const sourceIds = source("main [id]").toArray().map(element => source(element).attr("id"));
  for (const id of sourceIds) assert(ids.includes(id), `${page.outputPath}: removed existing anchor ${id}`);
  const diagrams = source(".mermaid").toArray().map(element => diagramSource(source, element));
  assert.deepEqual(diagrams, english(".mermaid").toArray().map(element => diagramSource(english, element)), `${page.outputPath}: diagram source was rewritten`);
  const localizedDiagrams = diagrams.map((diagram, index) => localizeDiagram(diagram, page.language, page.slug, index));
  assert.deepEqual($(".diagram-code code").toArray().map(element => $(element).text()), localizedDiagrams, `${page.outputPath}: incorrect diagram translation`);
  assert.equal($('script[src*="cdn."]').length, 0, "Diagrams must be self-hosted.");
}

for (const [filename, $] of renderedDocuments) {
  for (const element of $("a[href], link[href], script[src], img[src], iframe[src], source[src], video[src], video[poster]").toArray()) {
    const value = $(element).attr("href") || $(element).attr("src") || $(element).attr("poster");
    if (!value || /^(?:https?:|mailto:|data:|tel:|\/\/)/.test(value)) continue;
    const [pathAndQuery, fragment] = value.split("#");
    const path = decodeURIComponent(pathAndQuery.split("?")[0]);
    const destination = path ? resolve(dirname(filename), path) : filename;
    assert(destination === output || destination.startsWith(output + "\\" ) || destination.startsWith(output + "/"), `Link escapes output: ${value}`);
    assert(existsSync(destination), `${filename}: missing local link ${value}`);
    if (fragment && destination.endsWith(".html")) {
      const target = renderedDocuments.get(destination) || load(readFileSync(destination, "utf8"));
      assert(target("[id]").toArray().some(node => target(node).attr("id") === decodeURIComponent(fragment)),
        `${filename}: missing anchor ${value}`);
    }
  }
}
assert(existsSync(resolve(output, "pagefind/pagefind.js")), "Missing search index.");
assert(existsSync(resolve(output, "assets/vendor/mermaid.min.js")), "Missing self-hosted Mermaid.");
assert(existsSync(resolve(output, "assets/vendor/mermaid-LICENSE.txt")), "Missing Mermaid licence.");
const entry = JSON.parse(readFileSync(resolve(output, "pagefind/pagefind-entry.json"), "utf8"));
for (const page of pages) assert(entry.languages[page.language], `Missing ${page.language} search index.`);
for (const excluded of ["planning", "architecture", ".copilot-tracking", "knowledge-docs"]) {
  assert(!existsSync(resolve(output, excluded)), `Internal content must not be published: ${excluded}`);
}
console.log(`Documentation: ${pages.length} pages; source prose, technical examples, languages, local links and search indexes preserved.`);
