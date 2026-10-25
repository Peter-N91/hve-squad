import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { load } from "cheerio";
import { assembleContent, embedConnectorTemplates, enhanceContent, headingIds, readLocales, pageOrder, readSource } from "../../scripts/docs-content.mjs";

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

test("connector guides explain consumer seats, arbitrary additions, and squad-local outputs in both languages", () => {
  for (const prefix of ["", "fr/"]) {
    const { $, raw } = readSource("connector", prefix);
    const text = $("main").text();
    for (const contractTerm of ["research-org", "implementation-org", "developer-delivery-orchestrator",
      "dotnet-practices", "data-quality", "squadRoot", "history/Squad Connector.md", "external, unverified"]) {
      assert(text.includes(contractTerm), `${prefix}connector: missing ${contractTerm}`);
    }
    for (const example of ["CONSUMER-GUIDE.md", "consumer-team.1.1.md"]) {
      assert($(`a[href$="/docs/templates/connector-example/${example}"]`).length > 0);
    }
    assert(!raw.includes("/blob/main/templates/connector-example/"));
    assert(!raw.includes("OneDrive"));
    assert(text.includes("/squad mode=autopilot"));
    assert.equal($("main h2").first().attr("id"), "consumer-walkthrough");
    assert($('a[href="#copy-the-templates"]').length > 0);
  }
});

test("connector guides document both builders and safe end-to-end runs in both languages", () => {
  for (const prefix of ["", "fr/"]) {
    const { $, raw } = readSource("connector", prefix);
    const text = $("main").text();
    for (const term of [
      "Squad Connector Builder", "Squad External Agent Builder",
      "New-SquadConnector.ps1", "Test-SquadConnectorManifest.ps1",
      "New-SquadExternalEndpoint.ps1", "Run-<id>-Connector.ps1",
      "Invoke-ExampleEndpoint", "REPLACE_CONNECTOR_ID", "unchanged",
      "awaiting", "external, unverified",
    ]) {
      assert(text.includes(term), `${prefix}connector: missing builder runbook term ${term}`);
    }
    assert(raw.includes("/squad-connector-builder mode=interactive"));
    assert(raw.includes("/squad-connector-builder mode=template"));
    assert(raw.includes("/squad-external-agent-builder action=create kind=orchestrator"));
    assert(raw.includes("/squad-external-agent-builder action=adapt kind=agent"));
    assert.match(text, prefix ? /identique octet par octet/ : /byte-identical/);
    assert.match(text, prefix ? /ne demande d'identifiants secrets/ : /asks for credentials/);
  }
});

test("connector guides keep retry exhaustion aligned with the unreachable runtime status", () => {
  for (const prefix of ["", "fr/"]) {
    const { $ } = readSource("connector", prefix);
    const rowFor = label => $("tr").filter((_, row) => $(row).find("td code").first().text() === label).first().text().replace(/\s+/g, " ");
    for (const label of ["retryCapDefault", "retryCap"]) {
      const row = rowFor(label);
      assert(row.includes("unreachable"), `${prefix}connector: ${label} must terminate as unreachable`);
      assert(!row.includes("failed"), `${prefix}connector: ${label} must not terminate as failed`);
    }
    assert(rowFor("unreachable").includes("retryCap"), `${prefix}connector: unreachable status must name retryCap exhaustion`);
  }
});

test("connector guides preserve the collision snapshot across ordinary resume", () => {
  for (const prefix of ["", "fr/"]) {
    const { $ } = readSource("connector", prefix);
    const text = $("main").text();
    const failedRow = $("tr").filter((_, row) => $(row).find("td code").first().text() === "failed").first().text();
    for (const term of ["<taskId>.snapshot.json", "<taskId>.request.json", "*.snapshot.json"]) {
      assert(text.includes(term), `${prefix}connector: missing durable resume term ${term}`);
    }
    assert(text.includes("validate") || text.includes("valide"));
    assert(text.includes("never") || text.includes("jamais"));
    assert(failedRow.includes("snapshot") || failedRow.includes("photographie"),
      `${prefix}connector: failed status must cover invalid collision snapshots`);
  }
});

test("connector guides retain completed history across confirmed binding changes", () => {
  for (const prefix of ["", "fr/"]) {
    const { $ } = readSource("connector", prefix);
    const paragraph = $("main p").filter((_, element) => $(element).text().includes("Connector Binding Retirement")).text();
    assert(paragraph.includes("decisions.md"), `${prefix}connector: retirement must be Scribe-owned decision evidence`);
    assert(paragraph.includes("Attribution"), `${prefix}connector: completed attribution must survive a binding change`);
    assert.match(paragraph, prefix ? /n'autorise aucune nouvelle/ : /grants no new dispatch/);
    assert.match(paragraph, prefix ? /confirmation de l'opérateur/ : /operator confirmation/);
    for (const term of ["Measure-SquadLedger.ps1", "Resolve-SquadConnectorHistory.ps1"]) {
      assert(paragraph.includes(term), `${prefix}connector: production ledger must preserve retired attribution`);
    }
    assert.match(paragraph, prefix ? /entiers/ : /integers/);
    assert.match(paragraph, prefix ? /dupliquée/ : /duplicate/);
    assert.match(paragraph, prefix ? /distinctes/ : /Disjoint/);
  }
});

test("connector guides explain the thin scripted lifecycle and durable private replay state", () => {
  for (const prefix of ["", "fr/"]) {
    const { $ } = readSource("connector", prefix);
    const paragraph = $("main p").filter((_, element) => $(element).text().includes("Invoke-SquadConnectorDispatch.ps1")).text();
    for (const term of ["Resolve-SquadConnectorDispatch.ps1", "dropPath/.squad-connector/<taskId>.state.json",
      "JSON", "narrative", "Scribe"]) {
      assert(paragraph.includes(term), `${prefix}connector: missing lifecycle boundary ${term}`);
    }
    assert.match(paragraph, prefix ? /jamais le/ : /never raw external/);
    assert.match(paragraph, prefix ? /entre processus/ : /across processes/);
    assert(paragraph.includes("taskId"), `${prefix}connector: native resume must retain its task id`);
    assert.match(paragraph, prefix ? /agent natif/ : /native/);
    assert.match(paragraph, prefix ? /renommage/ : /renaming/);
    assert.match(paragraph, prefix ? /JSON de délégation exact/ : /exact dispatch JSON/);
    assert.match(paragraph, prefix ? /premier résultat/ : /first result/);
    assert(paragraph.includes("* "), `${prefix}connector: provenance must keep its literal bullet prefix`);
  }
});

test("the consumer companion teaches onboarding rather than developer smoke tests", () => {
  const guide = readFileSync(new URL("../../docs/templates/connector-example/CONSUMER-GUIDE.md", import.meta.url), "utf8");
  for (let step = 1; step <= 6; step++) assert.match(guide, new RegExp(`^## Step ${step}:`, "m"));
  for (const term of ["connectors/research-agent.json", "connectors/delivery-workflow.json",
    "Default Execution", "Org Delivery", "dotnet-assessor", "gcp-assessor", "copy buttons"]) {
    assert(guide.includes(term), `Missing consumer instruction: ${term}`);
  }
  assert.match(guide, /asks for missing decisions one at a time/);
  assert.match(guide, /implementation coordinator/);
  assert.match(guide, /<taskId>\.snapshot\.json/);
  assert.match(guide, /ignores and never edits `\*\.snapshot\.json`/);
  assert.match(guide, /`Connector Binding Retirement`/);
  assert.match(guide, /cannot\s+authorize a new dispatch or an unlisted entry/);
  assert(!guide.includes("Build-SquadPlugin.ps1"));
  assert(!guide.includes("configuration-only test"));
});

test("both published connector guides embed eight downloadable templates with copy controls and normalized line endings", () => {
  const expected = [
    "manifest.research-agent.1.1.json", "manifest.delivery-workflow.1.1.json", "manifest.capability-assessor.1.1.json",
    "agents/consumer-research.agent.md", "agents/consumer-implementation-orchestrator.agent.md",
    "agents/consumer-implementation.agent.md", "agents/consumer-validation.agent.md", "agents/consumer-capability-assessor.agent.md",
  ];
  for (const prefix of ["", "fr/"]) {
    const { $ } = readSource("connector", prefix);
    const blocks = $("[data-connector-template]");
    assert.deepEqual(blocks.toArray().map(element => $(element).attr("data-connector-template")), expected);
    const tree = $("pre code").first().text();
    assert(tree.includes("connectors\\"));
    assert(tree.includes("delivery-workflow.json"));
    assert(tree.includes(".connector-drops\\"));
    assert(tree.includes("HVE/Scribe-managed squad state"));
    const ids = headingIds($);
    enhanceContent($, ids, readLocales()[prefix ? "fr" : "en"].ui, prefix ? "../" : "");
    for (const element of blocks.toArray()) {
      const block = $(element);
      const filename = block.attr("data-connector-template");
      const source = readFileSync(new URL(`../../docs/templates/connector-example/${filename}`, import.meta.url), "utf8").replace(/\r\n?/g, "\n");
      assert.equal(block.find("pre code").text(), source, `Template content drift: ${filename}`);
      assert.equal(block.find("[data-copy-target]").length, 1);
      const button = block.find("[data-copy-target]");
      assert.equal(button.attr("data-copy-target"), block.find("pre").attr("id"));
      assert(button.attr("aria-label").includes(block.find(".code-heading").clone().children().remove().end().text().trim()));
      assert.equal(block.find("a[download]").length, 1);
      assert(block.find("a[download]").attr("href").includes(filename));
      if (filename.endsWith(".json")) {
        const manifest = JSON.parse(source);
        assert.equal(manifest.schemaVersion, "1.1");
        assert.equal(manifest.transport, "file");
        if (filename.includes("delivery-workflow")) {
          assert.equal(manifest.endpointKind, "orchestrator");
          assert.deepEqual(manifest.roles, ["developer"]);
        }
      }
    }
  }
});

test("connector template embedding rejects unsupported paths and missing code containers", () => {
  for (const filename of ["../package.json", "agents/../../package.json", "C:\\private.json", "README.md"]) {
    const $ = load(`<main><details data-connector-template="${filename}"><pre><code></code></pre></details></main>`);
    assert.throws(() => embedConnectorTemplates($), /Invalid connector template path/);
  }
  assert.throws(() => embedConnectorTemplates(load('<main><div data-connector-template="manifest.research-agent.1.1.json"></div></main>')),
    /exactly one code block/);
  assert.throws(() => embedConnectorTemplates(load('<main><div data-connector-template="missing-template.json"><pre><code></code></pre></div></main>')),
    /ENOENT/);
});
