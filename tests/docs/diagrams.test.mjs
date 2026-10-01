import assert from "node:assert/strict";
import test from "node:test";
import { diagramSource, readSource } from "../../scripts/docs-content.mjs";
import { localizeDiagram } from "../../scripts/diagram-locales.mjs";

for (const slug of ["usage", "maintaining"]) {
  test(`${slug}: diagrams preserve graph topology and localize every declared label`, () => {
    const { $ } = readSource(slug);
    $(".mermaid").each((index, element) => {
      const source = diagramSource($, element);
      assert.equal(localizeDiagram(source, "en", slug, index), source);
      const translated = localizeDiagram(source, "fr", slug, index);
      const structure = text => text.split("\n").map(line => line
        .replace(/"[^"]*"/g, '"label"')
        .replace(/-- (?:yes|no|oui|non) -->/g, "-- answer -->")
        .replace(/-\. (?:fallback|repli) \.->/g, "-. fallback .->"));
      assert.deepEqual(structure(translated), structure(source));
      assert.notEqual(translated, source);
    });
  });
}

test("unknown diagram translations fail rather than displaying the wrong language", () => {
  assert.throws(() => localizeDiagram("flowchart TD", "es", "usage"), /Missing diagram translation/);
});
