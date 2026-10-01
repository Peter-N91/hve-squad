import { existsSync, lstatSync, readdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function validateTree(path) {
  const info = lstatSync(path);
  if (info.isSymbolicLink()) throw new Error(`Symlinks must not be published: ${path}`);
  if (info.isDirectory()) {
    for (const item of readdirSync(path)) validateTree(join(path, item));
  } else if (!info.isFile()) {
    throw new Error(`Expected a regular documentation file: ${path}`);
  }
}

export function validatePublicInputs() {
  for (const directory of ["docs", "site"]) {
    const path = join(root, directory);
    if (!lstatSync(path).isDirectory()) throw new Error(`Expected a documentation directory: ${directory}`);
    validateTree(path);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  validatePublicInputs();
  if (process.argv.includes("--clean")) {
    const output = join(root, "_site");
    if (existsSync(output)) {
      if (lstatSync(output).isSymbolicLink()) throw new Error("Refusing to clean a symlinked output directory.");
      rmSync(output, { recursive: true });
    }
  }
}
