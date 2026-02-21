import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const tauriDir = path.resolve(scriptDir, '..');
const appRoot = path.resolve(tauriDir, '..');
const tauriConfigPath = path.join(tauriDir, 'tauri.conf.json');

function extractNodeScriptPath(command) {
  const match = command.match(/^node\s+(\S+)\s+/);
  assert.ok(match, `Expected node command, got: ${command}`);
  return match[1];
}

test('beforeDevCommand references an existing script from app root', () => {
  const config = JSON.parse(fs.readFileSync(tauriConfigPath, 'utf8'));
  const scriptPath = extractNodeScriptPath(config.build.beforeDevCommand);
  const absoluteScriptPath = path.resolve(appRoot, scriptPath);

  assert.equal(
    fs.existsSync(absoluteScriptPath),
    true,
    `beforeDevCommand script not found at ${absoluteScriptPath}`,
  );
});

test('beforeBuildCommand references an existing script from app root', () => {
  const config = JSON.parse(fs.readFileSync(tauriConfigPath, 'utf8'));
  const scriptPath = extractNodeScriptPath(config.build.beforeBuildCommand);
  const absoluteScriptPath = path.resolve(appRoot, scriptPath);

  assert.equal(
    fs.existsSync(absoluteScriptPath),
    true,
    `beforeBuildCommand script not found at ${absoluteScriptPath}`,
  );
});
