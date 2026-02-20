# Skills Sync App

Native macOS app for monitoring and controlling skills sync.

## Features

- Sync health (`OK/FAILED/SYNCING`) + counts
- Host app with searchable full skill list
- Direct actions from app:
  - Open in Zed
  - Reveal in Finder
  - Make global (move project skill to global scope)
  - Delete canonical source (move to Trash)
  - Sync now

## Data contract

- Primary app state file: `~/Library/Application Support/SkillsSync/state.json`
- Native sync runtime: `/Users/fedosov/.config/ai-agents/skillssync/`

## Build

```bash
cd /Users/fedosov/Dev/ai-skills-widget
xcodegen generate
xcodebuild -project SkillsSync.xcodeproj -scheme SkillsSyncApp -configuration Debug -allowProvisioningUpdates build
xcodebuild -project SkillsSync.xcodeproj -scheme SkillsSyncApp -destination 'platform=macOS' -allowProvisioningUpdates test
```

## Notes

- Backend is fully in Swift (`SyncEngine`) inside the app target.
- `commands.jsonl` queue is no longer used.
- Delete action requires explicit confirmation in host app.
- Make global action is destructive and requires double confirmation in host app.
