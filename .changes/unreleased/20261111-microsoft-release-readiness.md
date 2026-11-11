---
bump: patch
type: Changed
---
<!--
Copyright (c) Microsoft Corporation.
Licensed under the MIT license.
-->

- **Prepare hve-squad for a Microsoft MIT release.** Align first-party copyright headers and community guidance, preserve third-party notices, and package the canonical `LICENSE.TXT` separately from upstream licenses.
- **Serve documentation fonts through Google Fonts.** Preserve Manrope, Source Sans 3 and JetBrains Mono styling with `display=swap` and system-font fallbacks, remove the five bundled WOFF2 files, and retain the font license notices and demo recordings.
- **Publish Mermaid runtime dependency notices.** Retain complete versioned legal text for all 66 embedded dependency identities, bind the unchanged runtime and build-only source map to an offline-validated inventory, and reject missing or altered published notices. Supplier license alternatives and unverified source commits remain explicit; this is not legal clearance.
