import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const releasesUrl = "https://github.com/Peter-N91/hve-squad/releases/tag/";
const bumpRank = { patch: 1, minor: 2, major: 3 };
const changeId = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const commitId = /^[0-9a-f]{40}$/;

function git(repositoryRoot, args, allowFailure = false) {
  try {
    return execFileSync("git", args, {
      cwd: repositoryRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    if (allowFailure) return null;
    const detail = error.stderr?.toString().trim();
    throw new Error(`Automatic pre-release documentation detection failed${detail ? `: ${detail}` : "."}`);
  }
}

export function readPendingChangeCommits(release, repositoryRoot = root) {
  const commits = new Set();
  if (!release.previewTag) return commits;
  if (git(repositoryRoot, ["rev-parse", "--is-inside-work-tree"], true) !== "true") {
    throw new Error("Automatic pre-release documentation detection requires a Git checkout.");
  }
  if (git(repositoryRoot, ["rev-parse", "--is-shallow-repository"]) === "true") {
    throw new Error("Automatic pre-release documentation detection requires full Git history. Use fetch-depth: 0.");
  }
  for (const id of release.pendingChanges) {
    const path = `.changes/unreleased/${id}.md`;
    if (git(repositoryRoot, ["ls-files", "--error-unmatch", "--", path], true) === null) continue;
    const commit = git(repositoryRoot, ["log", "--first-parent", "--no-patch", "-1", "--format=%H", "--diff-filter=A", "--", path]);
    if (!commitId.test(commit)) throw new Error(`${path}: could not resolve the commit that added this pending fragment.`);
    commits.add(commit);
  }
  return commits;
}

function countMatches(value, pattern) {
  return value.match(pattern)?.length ?? 0;
}

export function annotateReleaseSource(raw, changedLines, fileAddedByPendingChange = false) {
  const changed = changedLines instanceof Set ? changedLines : new Set(changedLines);
  if (!changed.size) return raw;
  const newline = raw.includes("\r\n") ? "\r\n" : "\n";
  const lines = raw.split(/\r?\n/);
  const contentLines = new Set();
  const headings = [];
  const stack = [];
  let inHero = false;
  let inMain = false;
  let linkDepth = 0;

  lines.forEach((line, index) => {
    if (/<header\b[^>]*\bclass=(?:"[^"]*\bhero\b[^"]*"|'[^']*\bhero\b[^']*')/i.test(line)) inHero = true;
    if (/<main\b/i.test(line)) inMain = true;
    const inContent = inHero || inMain;
    if (inContent) contentLines.add(index + 1);

    const heading = inContent ? line.match(/<h([1-4])\b/i) : null;
    if (heading) {
      const prefix = line.slice(0, heading.index);
      const depthAtHeading = linkDepth
        + countMatches(prefix, /<a\b/gi)
        - countMatches(prefix, /<\/a\s*>/gi);
      const level = Number(heading[1]);
      while (stack.length && stack.at(-1).level >= level) stack.pop();
      const item = {
        line: index + 1,
        level,
        insideLink: depthAtHeading > 0,
        parent: stack.at(-1) ?? null,
      };
      headings.push(item);
      stack.push(item);
    }

    linkDepth += countMatches(line, /<a\b/gi) - countMatches(line, /<\/a\s*>/gi);
    if (/<\/header\s*>/i.test(line)) inHero = false;
    if (/<\/main\s*>/i.test(line)) inMain = false;
  });

  const safeHeadings = headings.filter(heading => !heading.insideLink);
  const fallback = safeHeadings.find(heading => heading.level === 1) ?? safeHeadings[0];
  if (!fallback) return raw;

  let selected;
  if (fileAddedByPendingChange) {
    selected = [fallback];
  } else {
    const selectedByLine = new Map();
    for (const line of changed) {
      if (!contentLines.has(line)) continue;
      let nearest = null;
      for (const heading of safeHeadings) {
        if (heading.line > line) break;
        nearest = heading;
      }
      selectedByLine.set((nearest ?? fallback).line, nearest ?? fallback);
    }
    const selectedLines = new Set(selectedByLine.keys());
    selected = [...selectedByLine.values()].filter(heading => {
      for (let parent = heading.parent; parent; parent = parent.parent) {
        if (selectedLines.has(parent.line) && changed.has(parent.line)) return false;
      }
      return true;
    });
  }

  for (const heading of selected) {
    const index = heading.line - 1;
    if (/\bdata-release-(?:auto|change)=/i.test(lines[index])) continue;
    lines[index] = lines[index].replace(/<h([1-4])\b/i, match => `${match} data-release-auto=""`);
  }
  return lines.join(newline);
}

function pendingLinesForSource(repositoryRoot, sourcePath, pendingCommits) {
  if (!pendingCommits.size || git(repositoryRoot, ["ls-files", "--error-unmatch", "--", sourcePath], true) === null) {
    return { changedLines: new Set(), fileAddedByPendingChange: false };
  }
  const changedLines = new Set();
  const blame = git(repositoryRoot, ["blame", "--line-porcelain", "--", sourcePath]);
  for (const line of blame.split(/\r?\n/)) {
    const header = line.match(/^([0-9a-f]{40}) \d+ (\d+)(?: \d+)?$/);
    if (header && pendingCommits.has(header[1])) changedLines.add(Number(header[2]));
  }
  const addedCommit = git(repositoryRoot, ["log", "-1", "--format=%H", "--diff-filter=A", "--", sourcePath]);
  return {
    changedLines,
    fileAddedByPendingChange: pendingCommits.has(addedCommit),
  };
}

export function createAutomaticReleaseAnnotator(release, repositoryRoot = root) {
  const pendingCommits = readPendingChangeCommits(release, repositoryRoot);
  const cache = new Map();
  return (sourcePath, raw) => {
    if (!pendingCommits.size) return raw;
    if (!cache.has(sourcePath)) {
      cache.set(sourcePath, pendingLinesForSource(repositoryRoot, sourcePath, pendingCommits));
    }
    const { changedLines, fileAddedByPendingChange } = cache.get(sourcePath);
    return annotateReleaseSource(raw, changedLines, fileAddedByPendingChange);
  };
}

export function resolveReleaseInfo(manifest, fragments) {
  const stableVersion = manifest.match(/^version:[ \t]*(\d+\.\d+\.\d+)[ \t]*\r?$/m)?.[1];
  if (!stableVersion) throw new Error("The APM version must be X.Y.Z.");
  let bump = "patch";
  const pendingChanges = fragments.map(({ name, content }) => {
    const id = name.replace(/\.md$/, "");
    if (!changeId.test(id) || !name.endsWith(".md")) throw new Error(`Invalid change fragment name: ${name}`);
    const match = content.match(/^\s*---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n([\s\S]*)$/);
    if (!match) throw new Error(`${name}: missing change fragment frontmatter.`);
    const fields = Object.fromEntries(match[1].split(/\r?\n/).flatMap(line => {
      const field = line.match(/^\s*([A-Za-z_]+)\s*:\s*(.+?)\s*$/);
      return field ? [[field[1].toLowerCase(), field[2].replace(/^["']|["']$/g, "").toLowerCase()]] : [];
    }));
    if (!Object.hasOwn(bumpRank, fields.bump)) throw new Error(`${name}: invalid release bump.`);
    if (!/^(added|changed|deprecated|removed|fixed|security)$/.test(fields.type ?? "")) {
      throw new Error(`${name}: invalid change type.`);
    }
    if (!/^\s*-\s/m.test(match[2].trim())) throw new Error(`${name}: the change body must contain markdown bullets.`);
    if (bumpRank[fields.bump] > bumpRank[bump]) bump = fields.bump;
    return id;
  });
  const parts = stableVersion.split(".").map(Number);
  const index = { major: 0, minor: 1, patch: 2 }[bump];
  parts[index]++;
  for (let i = index + 1; i < parts.length; i++) parts[i] = 0;
  const stableTag = `v${stableVersion}`;
  const previewTag = pendingChanges.length ? `v${parts.join(".")}-pre` : null;
  return {
    stableVersion, stableTag, stableUrl: releasesUrl + stableTag,
    previewTag, previewUrl: previewTag ? releasesUrl + previewTag : null, pendingChanges,
  };
}

export function readReleaseInfo(repositoryRoot = root) {
  const directory = resolve(repositoryRoot, ".changes", "unreleased");
  const fragments = existsSync(directory) ? readdirSync(directory, { withFileTypes: true })
    .filter(entry => entry.isFile() && entry.name.endsWith(".md") && entry.name !== "README.md")
    .map(entry => ({ name: entry.name, content: readFileSync(resolve(directory, entry.name), "utf8") })) : [];
  return resolveReleaseInfo(readFileSync(resolve(repositoryRoot, "apm.yml"), "utf8"), fragments);
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
    if (!release.pendingChanges.includes(id)) return;
    addBadge(element);
  });
  if (release.previewTag) $("main [data-release-auto]").each((index, element) => addBadge(element));
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
