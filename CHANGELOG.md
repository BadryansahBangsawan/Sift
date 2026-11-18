# Changelog

All notable user-facing changes to Sift. Sift was called PureMac before 4.0.0.

## Unreleased

### Fixed

- `sift-cli uninstall` now lists the app's leftover files under `~/Library`
  (preferences, caches, containers and the rest). It previously reported only
  the app bundle, so the data it promised to clean stayed on disk.
- `sift-cli uninstall` now lists a LaunchAgent whose `Label` is the app's
  bundle identifier even when the file name differs.
- `sift-cli optimize` and `sift-cli doctor` now report memory in the binary
  units macOS uses, so a 16 GB Mac reads 16 GB instead of 17.2 GB.
- The menu bar popover now quotes disk usage in the same decimal units as the
  Overview. A 245.1 GB disk no longer reads 228.4 GB there.

## 4.0.1

### Changed

- New logo: a brass grain resting on a sieve while the small grains fall
  through. Sift keeps what matters and lets only the junk go. It replaces
  the "S" tile in the app icon, the sidebar, Settings, onboarding, the menu
  bar monitor and the website, and the README screenshots show it.
- Releases can be published without a Developer ID: an ad-hoc signed,
  not notarized build with first-launch instructions (Open Anyway).
- Documentation rewritten for Sift 4: README, the six translated READMEs,
  the website, the CLI guide and the Apple features notes. Contribution
  guides, the sponsor link and the star-history chart were removed; Sift is
  maintained by one person.

### Fixed

- The Duplicates "Clear" button now reads as "deselect" in every language
  (French, Italian and Portuguese said "clean" or "no problem").

## 4.0.0

PureMac is now Sift. The app, the command-line tool and the release artifacts use
the new name, and the interface has been rebuilt around a new design system.

### Redesign

- New window shell: a floating rail replaces the split-view sidebar, with the app
  title bar hidden, the current size shown next to each category, and weekly
  schedule details in the rail.
- Overview rebuilt around a proportional disk meter, storage chips, "Where it
  sits", "Biggest single wins", battery health, startup items and space reclaimed
  this month.
- Every cleanup category and tool screen now uses one layout: filters, a row
  list, and a pinned selection bar with a running total.
- Settings rebuilt as a sub-navigation with grouped row cards: General,
  Cleaning, Schedule, Appearance, Permissions and Updates.
- New type and colour system (Archivo, Archivo Narrow, Chivo Mono; brass accent
  by default) and a new Sift app icon.

### New

- Project junk: finds node_modules, .venv, target, .build and similar folders
  in the project folders you choose. A folder is listed only when its project
  file sits next to it, its contents look generated and git ignores it (never
  when git tracks anything inside it); hidden tool folders such as agent
  worktrees are left alone. Folders are checked again and moved to the Trash.
  Never part of Smart Scan or scheduled cleanup.
- Apple Intelligence: turn it off feature by feature (keep the ones you use),
  ask macOS's asset service to delete the on-device models, and block them
  from downloading again with a configuration profile you approve in System
  Settings. Optional switches for Mac Analytics, personalized ads, Siri and
  search improvement sharing, Spotlight web results and a few macOS pop-ups.
  Every change is listed for review first and can be undone. Ported from
  RemoveMacAI and pared (both MIT); requires Apple silicon and macOS 15.1+.
- AI tools: its own cleanup row for caches and logs of Claude, Claude Code,
  omp, ChatGPT, Cursor, Codex, Ollama, LM Studio and similar tools. Chat and
  session history and the Claude VM image are listed but never preselected,
  and go to the Trash; memory folders, settings and credentials are never
  touched.
- Trash category: Sift measures `~/.Trash` and empties it through Finder after a
  confirmation. It is read-only inside Sift, never bulk-selected, scheduled or
  auto-cleaned.
- Performance detail: CPU history, a wired/active/compressed memory breakdown,
  battery charge and health, and launchd status for startup items.
- Uninstaller: app version, category and last-opened date, a running-app guard
  with a Quit action, and a dry-run plan before removal.
- Weekly schedules choose a day and hour, and the rail shows when the next run
  is due.
- Large-file threshold slider, an accent colour picker, and a switch for
  not-downloaded iCloud placeholders in large-file and installer scans.
- Cleanup history records the category and title of each run, so the dashboard
  can show what was reclaimed this month.
- The new interface is localized in all thirteen supported languages.

### Changed

- Bundle identifier is `com.sift.app` (previously `com.puremac.app`); the app,
  its Application Support folder and its helper identifiers are named Sift.
- The command-line tool is now `sift-cli` (previously `puremac`). Homebrew
  already ships an unrelated `sift` formula, so the short name is not used.
  `sift-cli` reads `~/.config/sift` and falls back to `~/.config/puremac`.
- Update checks, documentation links and Homebrew casks point at
  `BadryansahBangsawan/Sift`; releases from the old repository are rejected.

### Fixed

- System junk no longer offers everything in `/tmp`: only entries you own
  that have been untouched for three days and hold no repository or socket,
  and never preselected.
- Sift no longer offers its own `.lproj` language files for removal.
- A malformed line in the CLI ignore file is skipped with a warning instead of
  dropping every protected path.
- The scheduled-cleanup label stays on one line, and the app icon shadow scales
  with the icon size instead of reading as a grey band at small sizes.

### Migration notes

- **Settings and history migrate automatically on first launch.** Sift copies
  the existing PureMac preferences and `~/Library/Application Support/PureMac`
  into the new locations. The PureMac data is left untouched.
- **Full Disk Access must be granted again.** macOS ties the permission to the
  bundle identifier, so add Sift in System Settings > Privacy & Security > Full
  Disk Access; the old PureMac entry can be removed.
- **The CLI is now `sift-cli` and still reads the old config.**
  `~/.config/puremac/config.json` and `ignore` are used until the first save,
  which writes to `~/.config/sift`.
