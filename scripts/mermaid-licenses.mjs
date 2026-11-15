// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const vendor = "site/assets/vendor";
const manifestName = "mermaid-runtime-licenses.json";
const noticeName = "mermaid-THIRD-PARTY-NOTICES.txt";
const digestPattern = /^[a-f0-9]{64}$/;
const fail = message => { throw new Error(`Mermaid runtime licenses: ${message}`); };
const requireValue = (condition, message) => { if (!condition) fail(message); };

export const sha256 = value => createHash("sha256").update(value).digest("hex");
export const normalizeLegalText = value => value.toString("utf8").replace(/\r\n/g, "\n");

export function legalBlock(kind, id, text) {
  return `[[BEGIN ${kind} ${id}]]\n${normalizeLegalText(text)}\n[[END ${kind} ${id}]]\n`;
}

function extractBlock(text, kind, id) {
  const begin = `[[BEGIN ${kind} ${id}]]\n`;
  const end = `\n[[END ${kind} ${id}]]\n`;
  const start = text.indexOf(begin);
  requireValue(start !== -1 && text.indexOf(begin, start + begin.length) === -1,
    `${id}: missing or duplicate ${kind.toLowerCase()} section.`);
  const finish = text.indexOf(end, start + begin.length);
  requireValue(finish !== -1 && text.indexOf(end, finish + end.length) === -1,
    `${id}: missing or duplicate ${kind.toLowerCase()} section end.`);
  return text.slice(start + begin.length, finish);
}

function embeddedIdentities(sourceMap) {
  const identities = new Map();
  for (const source of sourceMap.sources) {
    requireValue(typeof source === "string", "source map contains a non-string source.");
    if (!source.includes("/node_modules/")) continue;
    const match = source.match(/\/\.pnpm\/([^/]+)\/node_modules\/((?:@[^/]+\/)?[^/]+)\//);
    requireValue(match, `unrecognized embedded dependency source: ${source}`);
    const [, folder, name] = match;
    const prefix = `${name.replace("/", "+")}@`;
    requireValue(folder.startsWith(prefix), `inconsistent embedded package folder: ${folder}`);
    const version = folder.slice(prefix.length).split("_")[0];
    requireValue(/^\d+\.\d+\.\d+(?:-[\w.-]+)?$/.test(version),
      `unrecognized embedded package version: ${folder}`);
    const identity = `${name}@${version}`;
    if (!identities.has(identity)) identities.set(identity, new Set());
    identities.get(identity).add(folder);
  }
  return identities;
}

function publicURL(value, context) {
  requireValue(typeof value === "string", `${context}: missing canonical public URL.`);
  let url;
  try { url = new URL(value); } catch { fail(`${context}: invalid canonical public URL.`); }
  requireValue(url.protocol === "https:" && !url.username && !url.password &&
    ["registry.npmjs.org", "github.com", "raw.githubusercontent.com", "unpkg.com"].includes(url.hostname),
  `${context}: expected a canonical public supplier URL.`);
}

export function validateRuntimeLicenses({ bundle, sourceMap, inventory, notice, published }) {
  requireValue(inventory?.schemaVersion === 1 && inventory.runtime?.name === "mermaid" &&
    inventory.runtime.version === "12.2.0", "unsupported or missing runtime inventory.");
  for (const [label, bytes, expected] of [
    ["bundle", bundle, inventory.runtime.bundle?.sha256],
    ["source map", sourceMap, inventory.runtime.sourceMap?.sha256],
  ]) {
    requireValue(bytes !== undefined && digestPattern.test(expected), `missing ${label} or pinned SHA-256.`);
    requireValue(sha256(bytes) === expected, `${label} SHA-256 drift; review the exact runtime and regenerate its legal evidence.`);
  }
  let map;
  try { map = JSON.parse(sourceMap.toString("utf8")); } catch { fail("source map is not valid JSON."); }
  requireValue(Array.isArray(map.sources) && map.sources.length === inventory.runtime.sourceMap.sourceCount,
    "source-map source count differs from the inventory.");
  const embedded = embeddedIdentities(map);
  requireValue(Array.isArray(inventory.packages), "missing package inventory.");
  const listed = new Set();
  for (const entry of inventory.packages) {
    requireValue(typeof entry.identity === "string" && !listed.has(entry.identity),
      `duplicate or missing inventory identity: ${entry.identity}`);
    listed.add(entry.identity);
    requireValue(entry.identity === `${entry.name}@${entry.version}` && embedded.has(entry.identity),
      `inventory identity is not embedded: ${entry.identity}`);
    requireValue(embedded.get(entry.identity).size === 1 &&
      embedded.get(entry.identity).has(entry.sourceMapPnPmFolder),
    `${entry.identity}: source-map package folder differs.`);
  }
  for (const identity of embedded.keys()) {
    requireValue(listed.has(identity), `missing embedded inventory identity: ${identity}`);
  }
  requireValue(listed.size === inventory.identityCount, "inventory identity count differs.");
  requireValue(notice !== undefined, `missing ${noticeName}.`);
  const text = normalizeLegalText(notice);
  requireValue(inventory.notice?.file === noticeName && digestPattern.test(inventory.notice.sha256),
    "missing whole-notice SHA-256.");
  for (const entry of inventory.packages) {
    const context = entry.identity;
    requireValue(typeof entry.licenseExpression === "string" && entry.licenseExpression.length > 0,
      `${context}: missing supplier license expression; no default license is allowed.`);
    requireValue(entry.sourceCommit === null || /^[a-f0-9]{40}$/.test(entry.sourceCommit),
      `${context}: sourceCommit must be a verified Git commit or null.`);
    requireValue(Array.isArray(entry.canonicalPublicURLs) && entry.canonicalPublicURLs.length > 0,
      `${context}: missing public provenance.`);
    for (const url of entry.canonicalPublicURLs) publicURL(url, context);
    requireValue(digestPattern.test(entry.sourceEvidence?.rawSHA256) &&
      typeof entry.sourceEvidence.verificationMethod === "string",
    `${context}: missing source hash or verification method.`);
    const section = extractBlock(text, "PACKAGE", context);
    requireValue(section.startsWith(`License expression: ${entry.licenseExpression}\n`),
      `${context}: notice license expression differs from the inventory.`);
    requireValue(Array.isArray(entry.texts) && entry.texts.some(item => item.kind === "license"),
      `${context}: missing complete license text.`);
    const textIds = new Set();
    for (const item of entry.texts) {
      requireValue(typeof item.sectionId === "string" && !textIds.has(item.sectionId),
        `${context}: missing or duplicate legal-text identity.`);
      textIds.add(item.sectionId);
      publicURL(item.canonicalPublicURL, `${context} ${item.member}`);
      requireValue(digestPattern.test(item.rawMemberSHA256) && digestPattern.test(item.rawTextSHA256) &&
        typeof item.sourceSection === "string", `${context}: missing raw legal-source evidence.`);
      const legalText = extractBlock(section, "TEXT", item.sectionId);
      requireValue(legalText.length > 0 && sha256(legalText) === item.sha256,
        `${context} ${item.member}: legal-text SHA-256 drift or missing legal text.`);
    }
    requireValue((section.match(/^\[\[BEGIN TEXT /gm) || []).length === entry.texts.length,
      `${context}: unexpected legal-text section.`);
    requireValue(sha256(section) === entry.noticeSectionSHA256, `${context}: package notice section SHA-256 drift.`);
  }
  requireValue((text.match(/^\[\[BEGIN PACKAGE /gm) || []).length === listed.size,
    "unexpected package notice section.");
  requireValue(sha256(text) === inventory.notice.sha256, "whole notice SHA-256 drift.");
  if (published) {
    requireValue(published.bundle !== undefined && sha256(published.bundle) === inventory.runtime.bundle.sha256,
      "published bundle is missing or has SHA-256 drift.");
    requireValue(published.notice !== undefined &&
      sha256(normalizeLegalText(published.notice)) === inventory.notice.sha256,
    `published ${noticeName} is missing or has SHA-256 drift.`);
    try { assert.deepEqual(published.inventory, inventory); }
    catch { fail(`published ${manifestName} is missing or differs from the source inventory.`); }
  }
  return { identityCount: listed.size, textCount: inventory.packages.reduce((sum, entry) => sum + entry.texts.length, 0) };
}

function read(rootPath, relative) {
  try { return readFileSync(resolve(rootPath, relative)); }
  catch { fail(`missing or unreadable ${relative}.`); }
}

function json(bytes, label) {
  try { return JSON.parse(bytes.toString("utf8")); }
  catch { fail(`${label} is not valid JSON.`); }
}

export function validateMermaidLicenses({ repositoryRoot = root, outputRoot } = {}) {
  const inventory = json(read(repositoryRoot, `${vendor}/${manifestName}`), manifestName);
  const inputs = {
    bundle: read(repositoryRoot, "node_modules/mermaid/dist/mermaid.min.js"),
    sourceMap: read(repositoryRoot, "node_modules/mermaid/dist/mermaid.min.js.map"),
    inventory,
    notice: read(repositoryRoot, `${vendor}/${noticeName}`),
  };
  if (outputRoot) {
    inputs.published = {
      bundle: read(outputRoot, "assets/vendor/mermaid.min.js"),
      notice: read(outputRoot, `assets/vendor/${noticeName}`),
      inventory: json(read(outputRoot, `assets/vendor/${manifestName}`), `published ${manifestName}`),
    };
    for (const [source, target] of [
      ["node_modules/mermaid/LICENSE", "assets/vendor/mermaid-LICENSE.txt"],
      ["node_modules/pagefind/LICENSE/LICENSE", "assets/vendor/pagefind-LICENSE.txt"],
    ]) {
      requireValue(read(repositoryRoot, source).equals(read(outputRoot, target)),
        `${target}: original supplier license differs from the installed file.`);
    }
  }
  return validateRuntimeLicenses(inputs);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = validateMermaidLicenses();
  console.log(`Mermaid runtime licenses: ${result.identityCount} embedded identities; ${result.textCount} legal texts verified offline.`);
}
