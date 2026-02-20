# SkillsSync Platform Workspace

This workspace contains the multiplatform sync engine for `skills` and `subagents`:

- `crates/skillssync-core`: shared domain engine and file-sync use-cases
- `crates/skillssync-cli`: `skillssync` CLI on top of `skillssync-core`
- `apps/skillssync-desktop/src-tauri`: Tauri shell exposing core commands
- `apps/skillssync-desktop/ui`: React + Vite frontend for desktop app
- `spec/`: `state.json` schema, fixtures, CLI contract, and platform capability matrix

## Quick start

```bash
cd platform
cargo test
cargo run -p skillssync-cli -- sync --trigger manual --json
cargo run -p skillssync-cli -- list-subagents --scope all --json
```

## Desktop

```bash
cd platform/apps/skillssync-desktop/ui
npm install

cd ../src-tauri
cargo tauri dev
```
