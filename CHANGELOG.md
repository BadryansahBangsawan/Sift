# Changelog

All notable user-facing changes to Sift. Sift was called PureMac before 4.0.0.

## Unreleased

### Apple Intelligence

- The Apple features screen can turn Apple Intelligence off per feature, delete
  its on-device model sets through Apple's asset service, and block them from
  downloading again with a configuration profile you approve in System Settings.
- Optional privacy and pop-up tweaks, with a Recommended preset and an undo
  journal that restores the values Sift changed.
- Ported from [RemoveMacAI](https://github.com/omlahore/RemoveMacAI), which builds
  on [pared](https://github.com/4evy/pared). Both are MIT; their notices are in
  [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

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
