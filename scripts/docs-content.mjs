import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { load } from "cheerio";
import { localizeDiagram } from "./diagram-locales.mjs";

export const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const pageOrder = ["index", "getting-started", "usage", "demo", "demo-1", "demo-2", "demo-3", "demo-4", "ecosystem", "maintaining", "troubleshooting", "contributing"];
export const navigationGroups = [
  { key: "start", pages: ["index", "getting-started", "usage"] },
  { key: "guides", pages: ["demo", "demo-1", "demo-2", "demo-3", "demo-4"] },
  { key: "reference", pages: ["ecosystem", "troubleshooting"] },
  { key: "project", pages: ["maintaining", "contributing"] },
];
export const publicUrl = "https://peter-n91.github.io/hve-squad/";

function validateMessages(reference, translated, path) {
  if (typeof reference === "string") {
    if (typeof translated !== "string" || !translated.trim()) throw new Error(`Missing translation: ${path}`);
    return;
  }
  if (!translated || typeof translated !== "object" || Array.isArray(translated)) throw new Error(`Invalid translation group: ${path}`);
  if (JSON.stringify(Object.keys(reference).sort()) !== JSON.stringify(Object.keys(translated).sort())) {
    throw new Error(`Incomplete translation group: ${path}`);
  }
  for (const key of Object.keys(reference)) validateMessages(reference[key], translated[key], `${path}.${key}`);
}

export function readLocales() {
  const locales = JSON.parse(readFileSync(resolve(repositoryRoot, "site/locales.json"), "utf8"));
  const english = locales.en;
  if (!english || english.prefix !== "") throw new Error("English must retain the root URLs.");
  const prefixes = new Set();
  for (const [code, locale] of Object.entries(locales)) {
    if (!/^[a-z]{2,3}(?:-[A-Za-z0-9]+)*$/.test(code)) throw new Error(`Invalid locale code: ${code}`);
    if (prefixes.has(locale.prefix) || (locale.prefix && !/^[a-zA-Z0-9-]+\/$/.test(locale.prefix))) {
      throw new Error(`Invalid or duplicate locale prefix: ${code}`);
    }
    prefixes.add(locale.prefix);
    if (typeof locale.name !== "string" || !locale.name.trim()) throw new Error(`Missing native language name: ${code}`);
    if (!["ltr", "rtl"].includes(locale.direction)) throw new Error(`Invalid writing direction: ${code}`);
    validateMessages(english.ui, locale.ui, `${code}.ui`);
    for (const slug of pageOrder) {
      if (!locale.pages[slug]) throw new Error(`Missing navigation label: ${code}/${slug}`);
    }
  }
  return locales;
}

export function readSource(slug, prefix = "") {
  const sourcePath = `docs/${prefix}${slug}.html`;
  const raw = readFileSync(resolve(repositoryRoot, sourcePath), "utf8");
  const $ = load(raw);
  if ($("main").length !== 1) throw new Error(`${sourcePath}: expected exactly one main element.`);
  if ($("body > header.hero").length !== 1) throw new Error(`${sourcePath}: expected the original hero header.`);
  return { $, raw, sourcePath };
}

export function assembleContent($) {
  const main = $("main");
  main.wrapInner('<div data-source-body></div>');
  main.prepend($("<div>").attr("data-source-hero", "").append($("body > header.hero").clone()));
  if ($("body > .demo-bar").length) {
    main.prepend($("<div>").attr("data-source-demo", "").append($("body > .demo-bar").clone()));
  }
}

export function diagramSource($, element) {
  const diagram = $(element).clone();
  diagram.find("br").each((index, node) => { $(node).replaceWith($("<span>").text("<br/>")); });
  return diagram.text();
}

export function headingIds($) {
  const used = new Set($("main [id]").toArray().map(element => $(element).attr("id")));
  return $("main h2, main h3").toArray().map(element => {
    const heading = $(element);
    if (heading.attr("id")) return heading.attr("id");
    const stem = heading.text().normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
      .toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "section";
    let id = stem;
    let count = 2;
    while (used.has(id)) id = `${stem}-${count++}`;
    used.add(id);
    return id;
  });
}

export function enhanceContent($, englishIds, ui, rootPrefix, language = "en", slug = "") {
  const main = $("main");
  const headings = main.find("h2, h3");
  if (headings.length !== englishIds.length) throw new Error("Translation must preserve all section headings.");
  const toc = [];
  headings.each((i, element) => {
    const heading = $(element);
    const id = englishIds[i];
    heading.attr("id", id);
    const label = heading.text();
    if (!heading.closest("a").length) {
      if (!heading.closest(".card, [data-host]").length) toc.push({ id, text: label, depth: Number(element.tagName.slice(1)) });
      const anchor = $("<a>").attr({ href: `#${id}`, class: "heading-anchor", "aria-label": `${ui.sectionLink}: ${label}`, "data-site-ui": "", "data-pagefind-ignore": "" }).text("#");
      heading.append(anchor);
    }
  });
  main.find('img[src$="assets/logo.svg"]').attr("src", `${rootPrefix}assets/logo.svg`);
  main.find(".hero-logo .wordmark").text("HVE Squad");
  main.find("source[src], video[src], a[href]").each((i, element) => {
    const node = $(element);
    const attribute = element.tagName === "a" ? "href" : "src";
    const value = node.attr(attribute);
    if (/^(?:\.\.\/)?assets\//.test(value || "")) node.attr(attribute, `${rootPrefix}${value.replace(/^\.\.\//, "")}`);
  });
  main.find("iframe").each((index, element) => {
    const frame = $(element);
    if (!frame.attr("title")) {
      const caption = frame.closest("figure").find("figcaption").text().replace(/\s+/g, " ").trim();
      frame.attr("title", caption || ui.documentation);
    }
    frame.attr("loading", "lazy");
  });
  main.find("table").each((i, element) => {
    const table = $(element);
    const label = table.prevAll("h2, h3").first().text().replace(/#$/, "") || ui.table;
    const existing = table.parent(".table-wrap");
    if (existing.length) {
      existing.addClass("table-scroll").attr({ tabindex: "0", role: "region", "aria-label": label });
    } else {
      table.wrap($("<div>").attr({ class: "table-scroll", tabindex: "0", role: "region", "aria-label": label }));
    }
    table.find("thead th").attr("scope", "col");
  });
  main.find("pre").each((i, element) => {
    const pre = $(element).attr({ tabindex: "0", "aria-label": ui.code });
    const id = pre.attr("id") || `code-sample-${i + 1}`;
    pre.attr("id", id);
    if (!pre.parent().hasClass("code-block")) pre.wrap('<div class="code-block"></div>');
    const block = pre.parent();
    const caption = block.children(".code-heading");
    const button = $("<button>").attr({
      type: "button", class: "copy-button js-only", "data-copy-target": id,
      "aria-label": `${ui.copy}: ${ui.code} ${i + 1}`, "data-site-ui": "", "data-pagefind-ignore": "",
    }).text(ui.copy);
    if (caption.length) {
      block.addClass("has-heading");
      const label = caption.text().trim();
      pre.attr("aria-label", label);
      button.attr("aria-label", `${ui.copy}: ${label}`);
      caption.append(button);
    } else {
      pre.before(button);
    }
  });
  main.find(".mermaid").each((index, element) => {
    const source = localizeDiagram(diagramSource($, element), language, slug, index);
    const label = `${ui.diagram} ${index + 1}`;
    const figure = $("<figure>").attr({ class: "diagram", "aria-label": label });
    const toolbar = $("<div>").attr({ class: "diagram-toolbar js-only", hidden: "", "data-site-ui": "", "data-pagefind-ignore": "" });
    toolbar.append($("<span>").text(label));
    toolbar.append($("<button>").attr({ type: "button", class: "diagram-zoom", "aria-pressed": "false" }).text(ui.diagramZoom));
    figure.append(toolbar);
    figure.append($("<div>").attr({ class: "diagram-render", hidden: "", "aria-label": label, role: "img", tabindex: "0", "data-site-ui": "", "data-pagefind-ignore": "" }));
    figure.append($("<p>").attr({ class: "diagram-error", role: "status", hidden: "", "data-site-ui": "", "data-pagefind-ignore": "" }).text(ui.diagramError));
    const details = $("<details>").attr({ class: "diagram-source", open: "", "data-pagefind-ignore": "" });
    details.append($("<summary>").attr("data-site-ui", "").text(ui.diagramSource));
    details.append($("<pre>").attr({ tabindex: "0", class: "diagram-code", "aria-label": ui.diagramSource }).append($("<code>").text(source)));
    figure.append(details);
    $(element).replaceWith(figure);
  });
  return { content: main.html(), toc };
}

export function buildPages(locales = readLocales()) {
  const pages = [];
  const manifest = readFileSync(resolve(repositoryRoot, "apm.yml"), "utf8");
  const version = manifest.match(/^version:\s*(\S+)/m)?.[1];
  if (!version) throw new Error("The APM version could not be read.");
  const hostLocales = JSON.parse(readFileSync(resolve(repositoryRoot, "site/host-locales.json"), "utf8"));
  for (const language of Object.keys(locales)) validateMessages(hostLocales.en, hostLocales[language], `${language}.host`);
  for (const slug of pageOrder) {
    const english = readSource(slug);
    const ids = headingIds(english.$);
    for (const [language, locale] of Object.entries(locales)) {
      const { $, sourcePath } = readSource(slug, locale.prefix);
      const rootPrefix = locale.prefix ? "../" : "";
      if ($("main h2, main h3").length !== ids.length) {
        throw new Error(`${sourcePath}: expected ${ids.length} section headings to match English.`);
      }
      assembleContent($);
      const { content, toc } = enhanceContent($, ids, locale.ui, rootPrefix, language, slug);
      const title = $("title").text();
      const description = $('meta[name="description"]').attr("content");
      if (!title || !description) throw new Error(`Missing title or description: ${sourcePath}`);
      const index = pageOrder.indexOf(slug);
      const adjacent = n => n >= 0 && n < pageOrder.length
        ? { url: `${pageOrder[n]}.html`, title: locale.pages[pageOrder[n]] } : null;
      const outputPath = `${locale.prefix}${slug}.html`;
      pages.push({
        language, direction: locale.direction, slug, title, description, content, toc, rootPrefix, outputPath,
        ui: { ...locale.ui, host: hostLocales }, label: locale.pages[slug], version,
        mainId: $("main").attr("id") || "main",
        footer: $("footer").html(),
        hasPageEnd: $("main .pager").length > 0,
        hasDiagrams: $("main .diagram").length > 0,
        canonical: publicUrl + outputPath, defaultCanonical: `${publicUrl}${slug}.html`,
        sourceUrl: `https://github.com/Peter-N91/hve-squad/blob/main/${sourcePath}`,
        nav: navigationGroups.map(group => ({
          label: locale.ui[group.key],
          pages: group.pages.map(id => ({ id, label: locale.pages[id], url: `${id}.html`, subpage: /^demo-\d+$/.test(id) })),
        })),
        languages: Object.entries(locales).map(([code, item]) => ({
          code, name: item.name, url: `${rootPrefix}${item.prefix}${slug}.html`,
          canonical: `${publicUrl}${item.prefix}${slug}.html`,
        })),
        previous: adjacent(index - 1), next: adjacent(index + 1),
      });
    }
  }
  return pages;
}
