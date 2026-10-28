import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const releasesUrl = "https://github.com/Peter-N91/hve-squad/releases/tag/";
const releasesApi = "https://api.github.com/repos/Peter-N91/hve-squad/releases";
const releaseBumps = new Set(["patch", "minor", "major"]);
const changeId = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function publishedTag(release, prerelease) {
  if (!release || release.draft !== false || release.prerelease !== prerelease
    || typeof release.tag_name !== "string"
    || !/^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(release.tag_name)
    || typeof release.published_at !== "string" || !Number.isFinite(Date.parse(release.published_at))) {
    throw new Error(`Invalid published ${prerelease ? "pre-release" : "stable release"} metadata.`);
  }
  return release.tag_name;
}

export function resolveReleaseInfo(published, fragments) {
  if (!published || !Array.isArray(published.releases)) throw new Error("Invalid published release list.");
  const stableTag = publishedTag(published.latest, false);
  const previews = published.releases.filter(release => {
    if (!release || typeof release.draft !== "boolean" || typeof release.prerelease !== "boolean") {
      throw new Error("Invalid published release list entry.");
    }
    if (release.draft || !release.prerelease) return false;
    publishedTag(release, true);
    return true;
  }).sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at));
  const previewTag = previews[0]?.tag_name ?? null;
  const pendingChanges = fragments.map(({ name, content }) => {
    const id = name.replace(/\.md$/, "");
    if (!changeId.test(id) || !name.endsWith(".md")) throw new Error(`Invalid change fragment name: ${name}`);
    const match = content.match(/^\s*---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n([\s\S]*)$/);
    if (!match) throw new Error(`${name}: missing change fragment frontmatter.`);
    const fields = Object.fromEntries(match[1].split(/\r?\n/).flatMap(line => {
      const field = line.match(/^\s*([A-Za-z_]+)\s*:\s*(.+?)\s*$/);
      return field ? [[field[1].toLowerCase(), field[2].replace(/^["']|["']$/g, "").toLowerCase()]] : [];
    }));
    if (!releaseBumps.has(fields.bump)) throw new Error(`${name}: invalid release bump.`);
    if (!/^(added|changed|deprecated|removed|fixed|security)$/.test(fields.type ?? "")) {
      throw new Error(`${name}: invalid change type.`);
    }
    if (!/^\s*-\s/m.test(match[2].trim())) throw new Error(`${name}: the change body must contain markdown bullets.`);
    return id;
  });
  return {
    stableVersion: stableTag.replace(/^v/, ""), stableTag, stableUrl: releasesUrl + stableTag,
    previewTag, previewUrl: previewTag ? releasesUrl + previewTag : null, pendingChanges,
  };
}

export async function fetchPublishedReleases(fetchImpl = fetch) {
  const headers = { Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" };
  const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
  if (token) headers.Authorization = `Bearer ${token}`;
  const request = async path => {
    const response = await fetchImpl(releasesApi + path, { headers, signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new Error(`GitHub release lookup failed (${response.status}): ${releasesApi + path}`);
    return response.json();
  };
  const [latest, firstPage] = await Promise.all([request("/latest"), request("?per_page=100&page=1")]);
  if (!Array.isArray(firstPage)) throw new Error("Invalid GitHub release list response.");
  const releases = [...firstPage];
  let batch = firstPage;
  for (let page = 2; batch.length === 100; page++) {
    batch = await request(`?per_page=100&page=${page}`);
    if (!Array.isArray(batch)) throw new Error("Invalid GitHub release list response.");
    releases.push(...batch);
  }
  resolveReleaseInfo({ latest, releases }, []);
  const metadata = ({ tag_name, draft, prerelease, published_at }) => ({ tag_name, draft, prerelease, published_at });
  return { latest: metadata(latest), releases: releases.map(metadata) };
}

export function readReleaseInfo(repositoryRoot = root) {
  const snapshot = resolve(repositoryRoot, ".docs-releases.json");
  if (!existsSync(snapshot)) throw new Error("Missing published release snapshot. Run npm run docs:build to fetch it.");
  const directory = resolve(repositoryRoot, ".changes", "unreleased");
  const fragments = existsSync(directory) ? readdirSync(directory, { withFileTypes: true })
    .filter(entry => entry.isFile() && entry.name.endsWith(".md") && entry.name !== "README.md")
    .map(entry => ({ name: entry.name, content: readFileSync(resolve(directory, entry.name), "utf8") })) : [];
  return resolveReleaseInfo(JSON.parse(readFileSync(snapshot, "utf8")), fragments);
}

export function previewBadge($, release, ui, label = ui.previewOnly) {
  const badge = $("<a>").attr({
    class: "prerelease-badge", href: "getting-started.html#testing-the-pre-release",
    title: `${ui.previewOnly}. ${ui.stable}: ${release.stableTag}.`,
    "data-site-ui": "", "data-pagefind-ignore": "",
  });
  badge.append('<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true" focusable="false"><path d="M9 3h6m-5 0v6L4 19a1.3 1.3 0 0 0 1 2h14a1.3 1.3 0 0 0 1-2L14 9V3M7 15h10"/></svg>');
  return badge.append($("<span>").text(`${label} ${release.previewTag}`));
}

export function addReleaseBadges($, release, ui) {
  const badged = new Set();
  const addBadge = element => {
    if (badged.has(element)) return;
    const node = $(element);
    if (node.parents("a, pre, code").length || node.is("a")) {
      throw new Error("Place release annotations outside links and copyable code samples.");
    }
    const badge = previewBadge($, release, ui);
    if (node.is("pre")) (node.parent(".code-block").length ? node.parent() : node).before(badge);
    else if (node.is("code")) node.after(badge);
    else if (node.is("h1, h2, h3, h4")) node.append(badge);
    else node.prepend(badge, " ");
    badged.add(element);
  };

  $("main [data-release-change]").each((index, element) => {
    const node = $(element);
    const id = node.attr("data-release-change");
    if (!changeId.test(id)) throw new Error(`Invalid data-release-change: ${id}`);
    if (node.parents("a, pre, code").length || node.is("a")) {
      throw new Error("Place data-release-change outside links and copyable code samples.");
    }
    if (!release.previewTag || !release.pendingChanges.includes(id)) return;
    addBadge(element);
  });
}

export function populateReleaseInstalls($, release, ui) {
  $("main [data-release-install]").each((index, element) => {
    const node = $(element);
    const channel = node.attr("data-release-install");
    if (!["stable", "preview"].includes(channel)) throw new Error(`Invalid installation channel: ${channel}`);
    const block = $("<div>").attr("data-release-generated", "");
    const tag = channel === "preview" ? release.previewTag : release.stableTag;
    if (tag) {
      const label = channel === "preview" ? ui.installPreview : ui.installStable;
      const url = channel === "preview" ? release.previewUrl : release.stableUrl;
      block.append($("<p>").text(`${label} `).append($("<a>").attr("href", url).text(tag)));
      block.append($("<pre>").append($("<code>").text(`apm install "Peter-N91/hve-squad#${tag}" --target copilot`)));
    } else {
      block.append($("<p>").text(ui.noPreview));
    }
    node.append(block);
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv[2] !== "--refresh") throw new Error("Usage: node scripts/docs-release.mjs --refresh");
  const published = await fetchPublishedReleases();
  writeFileSync(resolve(root, ".docs-releases.json"), `${JSON.stringify(published, null, 2)}\n`);
  const release = resolveReleaseInfo(published, []);
  console.log(`Documentation releases: stable ${release.stableTag}; pre-release ${release.previewTag ?? "none"}.`);
}
