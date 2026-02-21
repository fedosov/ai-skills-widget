#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const VALID_MODES = new Set(["dev", "build"]);
const CANDIDATE_DIRS = ["../ui", "ui", "."];

function printUsage() {
  console.error("Usage: node ./scripts/tauri-ui-command.mjs <dev|build> [--dry-run]");
}

function findUiDir() {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const tauriDir = path.resolve(scriptDir, "..");
  const roots = [process.cwd(), tauriDir];

  for (const root of roots) {
    for (const candidate of CANDIDATE_DIRS) {
      const dir = path.resolve(root, candidate);
      if (fs.existsSync(path.join(dir, "package.json"))) {
        return dir;
      }
    }
  }

  return null;
}

const args = process.argv.slice(2);
const mode = args[0];
const dryRun = args.includes("--dry-run");

if (!VALID_MODES.has(mode)) {
  console.error(`Invalid mode '${mode ?? ""}'. Expected one of: dev, build.`);
  printUsage();
  process.exit(1);
}

const uiDir = findUiDir();
if (!uiDir) {
  console.error(
    `Could not locate UI package.json. Checked candidates [${CANDIDATE_DIRS.join(", ")}] from cwd '${process.cwd()}' and script directory.`
  );
  process.exit(1);
}

const npm = process.platform === "win32" ? "npm.cmd" : "npm";
const commandArgs = ["--prefix", uiDir, "run", mode];

if (dryRun) {
  console.log(`Resolved UI directory: ${uiDir}`);
  console.log(`Dry run command: ${npm} ${commandArgs.join(" ")}`);
  process.exit(0);
}

const result = spawnSync(npm, commandArgs, { stdio: "inherit" });
if (typeof result.status === "number") {
  process.exit(result.status);
}

console.error("Failed to execute npm command.");
process.exit(1);
