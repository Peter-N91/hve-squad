import { validatePublicInputs } from "./scripts/docs-inputs.mjs";

export default function (config) {
  validatePublicInputs();
  config.addWatchTarget("docs");
  config.addWatchTarget("scripts/docs-content.mjs");
  config.addWatchTarget("scripts/diagram-locales.mjs");
  config.addPassthroughCopy({ "site/assets": "assets" });
  config.addPassthroughCopy({ "docs/assets/fonts": "fonts" });
  config.addPassthroughCopy({ "docs/assets/logo.svg": "assets/logo.svg" });
  config.addPassthroughCopy({ "docs/assets/favicon.svg": "assets/favicon.svg" });
  config.addPassthroughCopy({ "docs/.nojekyll": ".nojekyll" });
  config.addPassthroughCopy({ "docs/assets/hve-squad-single-squad.mp4": "assets/hve-squad-single-squad.mp4" });
  config.addPassthroughCopy({ "docs/assets/hve-squad-federation.mp4": "assets/hve-squad-federation.mp4" });
  config.addPassthroughCopy({ "docs/templates": "templates" });
  config.addPassthroughCopy({ "docs/squad-governance-report-2026-08-04.html": "squad-governance-report-2026-08-04.html" });
  config.addPassthroughCopy({ "node_modules/mermaid/dist/mermaid.min.js": "assets/vendor/mermaid.min.js" });
  config.addPassthroughCopy({ "node_modules/mermaid/LICENSE": "assets/vendor/mermaid-LICENSE.txt" });
  config.addFilter("jsonScript", value => JSON.stringify(value).replace(/</g, "\\u003c"));
  return {
    dir: { input: "site", output: "_site", includes: "_includes", data: "_data" },
    templateFormats: ["njk"],
    htmlTemplateEngine: false,
  };
}
