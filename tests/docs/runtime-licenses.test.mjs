// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  legalBlock, normalizeLegalText, sha256, validateMermaidLicenses, validateRuntimeLicenses,
} from "../../scripts/mermaid-licenses.mjs";

function fixture() {
  const bundle = Buffer.from("fixture runtime;\n");
  const sourceMap = Buffer.from(JSON.stringify({
    sources: ["../../../node_modules/.pnpm/example@1.2.3/node_modules/example/index.js"],
  }));
  const legalText = "Copyright fixture authors.\nFixture permission and warranty terms.\n";
  const sectionId = "example@1.2.3:1";
  const section = "License expression: MIT\n" + legalBlock("TEXT", sectionId, legalText);
  const notice = Buffer.from("Fixture notices\n" + legalBlock("PACKAGE", "example@1.2.3", section));
  const inventory = {
    schemaVersion: 1,
    runtime: {
      name: "mermaid", version: "12.2.0",
      bundle: { sha256: sha256(bundle) },
      sourceMap: { sha256: sha256(sourceMap), sourceCount: 1 },
    },
    identityCount: 1,
    notice: { file: "mermaid-THIRD-PARTY-NOTICES.txt", sha256: sha256(notice) },
    packages: [{
      identity: "example@1.2.3", name: "example", version: "1.2.3",
      sourceMapPnPmFolder: "example@1.2.3",
      licenseExpression: "MIT", sourceCommit: null,
      canonicalPublicURLs: ["https://registry.npmjs.org/example/1.2.3"],
      sourceEvidence: { rawSHA256: sha256("source"), verificationMethod: "Synthetic fixture." },
      noticeSectionSHA256: sha256(section),
      texts: [{
        sectionId, kind: "license", member: "LICENSE", sourceSection: "entire file",
        canonicalPublicURL: "https://registry.npmjs.org/example/-/example-1.2.3.tgz#LICENSE",
        rawMemberSHA256: sha256(legalText), rawTextSHA256: sha256(legalText),
        sha256: sha256(legalText),
      }],
    }],
  };
  return { bundle, sourceMap, inventory, notice };
}

test("the actual 66-identity inventory and complete legal text validate with LF or CRLF", () => {
  assert.deepEqual(validateMermaidLicenses(), { identityCount: 66, textCount: 69 });
  const read = relative => readFileSync(new URL(`../../${relative}`, import.meta.url));
  const actual = {
    bundle: read("node_modules/mermaid/dist/mermaid.min.js"),
    sourceMap: read("node_modules/mermaid/dist/mermaid.min.js.map"),
    inventory: JSON.parse(read("site/assets/vendor/mermaid-runtime-licenses.json")),
    notice: read("site/assets/vendor/mermaid-THIRD-PARTY-NOTICES.txt"),
  };
  for (const newline of ["\n", "\r\n"]) {
    const notice = Buffer.from(normalizeLegalText(actual.notice).replace(/\n/g, newline));
    assert.deepEqual(validateRuntimeLicenses({
      ...actual, notice,
      published: { bundle: actual.bundle, inventory: structuredClone(actual.inventory), notice },
    }), { identityCount: 66, textCount: 69 });
  }
  assert.deepEqual(validateRuntimeLicenses(fixture()), { identityCount: 1, textCount: 1 });
});

test("raw payload or source-map drift fails before legal validation", () => {
  for (const [field, label] of [["bundle", "bundle"], ["sourceMap", "source map"]]) {
    const inputs = fixture();
    inputs[field] = Buffer.concat([inputs[field], Buffer.from("\r\n")]);
    assert.throws(() => validateRuntimeLicenses(inputs), new RegExp(`${label} SHA-256 drift`));
  }
});

test("the embedded identity set rejects missing, duplicate and foreign inventory entries", () => {
  const missing = fixture();
  missing.inventory.packages = [];
  assert.throws(() => validateRuntimeLicenses(missing), /missing embedded inventory identity: example@1\.2\.3/);
  const duplicate = fixture();
  duplicate.inventory.packages.push(structuredClone(duplicate.inventory.packages[0]));
  assert.throws(() => validateRuntimeLicenses(duplicate), /duplicate or missing inventory identity/);
  const foreign = fixture();
  foreign.inventory.packages[0].identity = "foreign@1.2.3";
  foreign.inventory.packages[0].name = "foreign";
  assert.throws(() => validateRuntimeLicenses(foreign), /inventory identity is not embedded: foreign@1\.2\.3/);
  const changedMap = fixture();
  changedMap.sourceMap = Buffer.from(changedMap.sourceMap.toString().replaceAll("example", "foreign"));
  changedMap.inventory.runtime.sourceMap.sha256 = sha256(changedMap.sourceMap);
  assert.throws(() => validateRuntimeLicenses(changedMap), /inventory identity is not embedded: example@1\.2\.3/);
});

test("missing sections, tampered legal terms and absent expressions fail without a default license", () => {
  const missing = fixture();
  missing.notice = undefined;
  assert.throws(() => validateRuntimeLicenses(missing), /missing mermaid-THIRD-PARTY-NOTICES/);
  for (const kind of ["PACKAGE", "TEXT"]) {
    const inputs = fixture();
    inputs.notice = Buffer.from(inputs.notice.toString().replace(`[[BEGIN ${kind} `, "[[REMOVED "));
    assert.throws(() => validateRuntimeLicenses(inputs), /missing or duplicate .* section/);
  }
  const tampered = fixture();
  tampered.notice = Buffer.from(tampered.notice.toString().replace("Copyright fixture authors.", "Copyright someone else."));
  assert.throws(() => validateRuntimeLicenses(tampered), /example@1\.2\.3 LICENSE: legal-text SHA-256 drift/);
  const noLicense = fixture();
  noLicense.inventory.packages[0].licenseExpression = "";
  assert.throws(() => validateRuntimeLicenses(noLicense), /no default license is allowed/);
  const extraText = fixture();
  extraText.inventory.packages[0].texts.push(structuredClone(extraText.inventory.packages[0].texts[0]));
  assert.throws(() => validateRuntimeLicenses(extraText), /duplicate legal-text identity/);
});

test("published bundle, inventory and complete notice cannot be missing or altered", () => {
  for (const field of ["bundle", "inventory", "notice"]) {
    for (const missing of [true, false]) {
      const inputs = fixture();
      inputs.published = {
        bundle: inputs.bundle, inventory: structuredClone(inputs.inventory), notice: inputs.notice,
      };
      inputs.published[field] = missing ? undefined :
        field === "inventory" ? { ...inputs.inventory, identityCount: 0 } : Buffer.from("tampered");
      assert.throws(() => validateRuntimeLicenses(inputs), /published .*missing or (?:has SHA-256 drift|differs)/);
    }
  }
  const preamble = fixture();
  preamble.notice = Buffer.from(preamble.notice.toString().replace("Fixture notices", "Changed notices"));
  assert.throws(() => validateRuntimeLicenses(preamble), /whole notice SHA-256 drift/);
});
