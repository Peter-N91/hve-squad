import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const css = readFileSync(new URL("../../site/assets/site.css", import.meta.url), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");

function blockEnd(text, open) {
  let depth = 0;
  for (let index = open; index < text.length; index++) {
    if (text[index] === "{") depth++;
    if (text[index] === "}" && --depth === 0) return index + 1;
  }
  throw new Error("Unbalanced CSS block.");
}

const printStart = css.indexOf("@media print");
assert(printStart > -1, "The print stylesheet is missing.");
const printEnd = blockEnd(css, css.indexOf("{", printStart));
const printCss = css.slice(printStart, printEnd);
const screenCss = css.slice(0, printStart) + css.slice(printEnd);

const bodies = (text, selector) => [...text.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
  .filter(([, selectors]) => selector.test(selectors))
  .map(([, , body]) => body);

const midWord = /overflow-wrap:\s*anywhere|word-break:\s*break-(?:all|word)/;

test("table cells on screen never allow a mid-word break, so columns cannot shrink to a single letter", () => {
  const cells = bodies(screenCss, /\b(?:th|td)\b/);
  assert(cells.length);
  for (const body of cells) assert.doesNotMatch(body, midWord);
  assert(bodies(screenCss, /\b(?:th|td)\b[^{}]*\bcode\b/).some(body => /overflow-wrap:\s*normal/.test(body)), "Code inside cells must not inherit overflow-wrap: anywhere.");
});

test("a table frame scrolls horizontally when its columns do not fit", () => {
  assert(bodies(screenCss, /^\s*\.table-scroll\s*$/).some(body => /overflow-x:\s*auto/.test(body)));
});

test("print keeps cells breakable because paper cannot scroll", () => {
  assert(bodies(printCss, /\b(?:th|td)\b/).some(body => /overflow-wrap:\s*anywhere/.test(body)));
});
