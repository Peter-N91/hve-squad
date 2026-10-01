import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const script = readFileSync(new URL("../../site/assets/theme.js", import.meta.url), "utf8");

function startTheme(stored, dark = false, blocked = false, search = "") {
  const events = {};
  const dataset = {};
  let followSystem;
  const media = { matches: dark, addEventListener: (_, handler) => { followSystem = handler; } };
  const context = {
    document: { documentElement: { dataset, classList: { add() {} } }, querySelector() { return null; } },
    window: { location: { search }, matchMedia: () => media, addEventListener: (name, handler) => { events[name] = handler; } },
    URLSearchParams,
    localStorage: { getItem() { if (blocked) throw new Error("Storage denied"); return stored; } },
    console: { warn() {} },
  };
  vm.runInNewContext(script, context);
  return { dataset, events, media, followSystem };
}

test("first visit follows the OS and responds to OS changes", () => {
  const theme = startTheme(null, true);
  assert.equal(theme.dataset.theme, "dark");
  theme.media.matches = false;
  theme.followSystem();
  assert.equal(theme.dataset.theme, "light");
});

test("explicit preference wins over OS until System is selected", () => {
  const theme = startTheme("light", true);
  assert.equal(theme.dataset.theme, "light");
  theme.events["hve-theme-change"]({ detail: "dark" });
  assert.equal(theme.dataset.theme, "dark");
  theme.media.matches = false;
  theme.followSystem();
  assert.equal(theme.dataset.theme, "dark");
  theme.events["hve-theme-change"]({ detail: "system" });
  assert.equal(theme.dataset.theme, "light");
});

test("blocked storage still renders according to OS", () => {
  assert.equal(startTheme(null, true, true).dataset.theme, "dark");
});

test("invalid stored values fall back to System; tabs synchronize", () => {
  const theme = startTheme("not-a-theme", true);
  assert.equal(theme.dataset.themePreference, "system");
  theme.events.storage({ key: "hve-docs-theme", newValue: "light" });
  assert.equal(theme.dataset.theme, "light");
});

test("the existing scoutTheme URL override remains supported and validates values", () => {
  assert.equal(startTheme("light", false, false, "?scoutTheme=dark").dataset.theme, "dark");
  assert.equal(startTheme("dark", true, false, "?scoutTheme=light").dataset.theme, "light");
  assert.equal(startTheme("light", true, false, "?scoutTheme=invalid").dataset.theme, "light");
});
