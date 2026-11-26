# Changelog

All notable user-facing changes to Sift. Sift was called PureMac before 4.0.0.

## Unreleased

### Fixed

- Removing orphaned files with administrator approval no longer breaks on names
  with an apostrophe, and a crafted folder name can no longer run commands as
  root.
- `sift-cli uninstall` now checks whether an app is running by comparing its
  executable path literally, so a bundle whose name has parentheses or dots is
  no longer deleted while it is open. If the process list cannot be read, the
  uninstall stops instead of assuming the app is not running.
- `sift-cli purge` now offers a build folder (`target`, `node_modules`, `.venv`,
  …) only when the project file that generates it — `Cargo.toml`,
  `package.json`, `Package.swift` and the like — sits next to it, so a source
  folder that happens to share the name is left alone.
- The app-files scan and removal no longer follow a symlinked folder, so a link
  planted in Application Support cannot put files from another directory in the
  app's removal list or move them to the Trash.

## 4.1.0

### Changed

- Large & old files and Installers move to the Trash instead of being deleted
  permanently, so they can be recovered until the Trash is emptied.
- The “X is junk” headline and the disk meter count only junk. Large & old files
  and the Trash keep their own sizes and no longer inflate that total; when the
  only rows found are personal files, the Overview says they are reviewable.
- A scheduled auto-clean moves what it removes to the Trash instead of deleting
  it: it runs while nobody is watching, so its cleanup stays recoverable. Rows
  it cannot trash — Docker prune, simulator runtimes, anything that needs an
  administrator password — stay selected for the next manual clean, and the
  history says "Moved to Trash" instead of counting those bytes as freed.
- Arabic lays out right-to-left: the rail sits on the right, chevrons and the
  Back arrow point the other way, the storage meter and the progress bars fill
  from the right, and the Where-it-sits rows, the excluded-folder chips, the
  Settings slider and the menu-bar popover mirror with the window. macOS gives
  an app the system's direction and not its own, so every window, the Settings
  scene and the popover now state the direction of the language they resolved;
  the other twelve languages stay left-to-right.

## 4.0.2

### Fixed

- The rail's schedule card keeps its title on one line when it fits — English
  had started reading "Scheduled" / "scan" / "Off" on three lines — and wraps
  only a title that really is wider than the card. The status line below the
  title stays on one line, so "Off" and "Daily" are always visible.
- The Leftovers page is called "Leftovers" above the heading and in the window
  title, and shows a count only once a scan has finished: it used to say
  "Orphaned Files (0)" on a page that had not looked yet.
- The Leftovers empty state and its button are translated: twelve languages
  showed the English "No Leftovers" and "Scan for leftover files". The
  scanning line in eight languages also said "orphaned files" next to a screen
  called Reste/Restos/残存ファイル, and now says the same thing the screen
  does. A test reads every literal the UI shows and fails when one is missing
  from any of the 13 tables.
- Labels no longer truncate in other languages at the 1080 pt minimum window:
  the storage capsules fit their label and value (the label moves to a second
  line when the slice is narrow) and rail rows wrap instead of clipping, in all
  13 localizations.
- The auto-clean setting no longer says it moves selected files to the Trash.
  An unattended clean deletes them, and the copy now says so.
- Developer cache rows (Xcode, Homebrew, npm, Docker, language files) show
  their real Modified date instead of a dash, so the age filter can judge them.
- The Leftovers page no longer says "No Orphaned Files" before it has looked:
  it shows "Not scanned yet" first, and "Couldn't compare installed apps" when
  the scan had no app list to compare against.
- The window no longer freezes while a Leftovers scan fetches the app list.
  Listing every installed app ran on the main actor and took seconds; it now
  runs on the scan's background task.
- Finder and WebKit metadata are no longer offered as leftovers: `.DS_Store`
  files, WebKit's shared LocalStorage folder and the SwiftPM cache belong to no
  app, so "the owner is uninstalled" said nothing about them.
- Leftovers no longer lists installed apps' own data. The scan ran against
  whatever the launch refresh had loaded so far, so with the installed-app list
  still empty every folder looked orphaned (44 rows on a machine that has 20).
  It now fetches the list first and, if it still has none, reports nothing and
  says why.
- A category you just emptied stays scanned: the page says "No files found"
  instead of "not scanned yet", the Overview row keeps its "0 items", and an
  emptied Trash no longer claims it was never scanned.
- Xcode Archives are no longer pre-selected or deleted outright. They hold your
  shipped builds and the dSYMs needed for crash reports and cannot be
  regenerated, so the row is opt-in, says what it holds, moves to the Trash, and
  stays out of an unattended scheduled clean unless you select it.
- A cleanup that skipped a row on purpose (an excluded path, the Trash itself,
  Claude running, a session you resumed, a temp entry that turned live, a
  symlink or a path outside the folders Sift cleans) no longer reports
  "N item(s) need Full Disk Access" and offers a Grant Access retry that can
  never work. It shows the reason instead.
- Pages are named the way the rail names them: "Space explorer", "Duplicates",
  "Similar photos", "Apple features", "App updates", and the Leftovers screen
  and onboarding rows ("Overview", "Uninstaller", "Leftovers") no longer use a
  second set of names.
- VoiceOver hears the cleanup search field and its clear button as two
  controls: the field is named by its prompt and the × is "Clear search", not
  both "Filter cleanup files".
- The rail's schedule card says "Scheduled scan" — matching Settings' "Enable
  scheduled scanning" — until auto-clean is on, when it says "Scheduled
  cleanup". It used to promise a cleanup for a schedule that only scans.
- App updates now says when it last checked ("Last checked 1 minute ago",
  "Last checked just now") as one sentence in every language. The eyebrow used
  to render a live duration — "1 min, 19 secs" — that ticked every second and
  never said "ago", glued to a separate "Last checked" fragment.
- Cleanup history now names each row the way the app names it today ("AI
  tools", "System junk", "Developer caches") and in the language on screen.
  Records written by an older build keep their meaning: their stored text is
  read back through every shipped language.
- The removal sheet and the selection bar list files in the same order as the
  list (name, size or date) instead of the order the scan produced; the
  dashboard's sheet, which has no sort control, reads largest first.
- The Uninstaller footer now says what the selection is on a line of its own
  ("25 items, 1.12 GB") above the buttons; at the minimum window width the
  summary used to be squeezed to a few points between "Dry run" and "Review
  removal", and its wording now follows the plural rules ("1 item").
- Arabic no longer loses the size in a count of zero, one or two files, and
  no longer crashes there: a label such as "1 item, 2 MB" put the size in the
  number's place and read `لا عناصر، (null)` before the crash.
- Sizes no longer read "Zero KB" or "999 bytes" in the Uninstaller, its
  leftovers, the History rows, the scan notification or `Sift scan`: every
  size in the app now comes from the one formatter the dashboard uses, so an
  empty folder reads "0 KB".
- Overview "Where it sits" no longer clips its category names at the minimum
  window width. The row gave half the leftover space to the meter, so
  "Developer caches" read "Developer c…" while the meter still had room to
  shrink; the label now keeps its full width and the meter gives way first.
- AI tools no longer moves a session transcript to the Trash when you resumed
  that session after the scan. The scan already treats a session touched in the
  last ten minutes as open; cleanup now re-checks the transcript before
  removing it, so a running agent keeps writing to its own history.
- System Junk no longer repeats the AI tool log folders (for example
  `~/Library/Logs/Claude`) that the AI tools category already lists, so the
  total junk figure is no longer inflated by the same log bytes counted twice.
- Biggest single wins no longer re-sorts every scanned row with locale-aware
  comparison on each cleanup update; on a 3000-row cleanup that sort was the
  main-thread stall behind the remaining freeze.
- Cleaning no longer republishes progress for every removed item. A large
  cleanup asked the window to redraw thousands of times, which looked like the
  app freezing for seconds; it now updates about once per percent.
- Purgeable Space lists the single purge row, so its total matches what the
  category can reclaim; Time Machine snapshots stay on the Performance page
  with their own delete action.
- Emptied Trash no longer counts a file it could not delete — for example an
  excluded, in-use item — as freed space.
- Battery status no longer reports "Charging" while macOS is holding the charge
  at a percentage — optimised charging's "AC attached; not charging".
- AI tools no longer report space as freed when opt-in chat history and the
  Claude VM image are moved to the Trash, where they still take up room until
  the Trash is emptied.
- Xcode Junk no longer reports XcodeBuildMCP DerivedData as freed while it sits
  in the Trash; the bytes count once, when the Trash is emptied.
- User Cache no longer repeats the Xcode caches and AI tool caches that Xcode
  Junk and AI tools already list, so the total junk figure is no longer
  inflated by the same bytes counted twice.
- `sift-cli uninstall` now lists the app's leftover files under `~/Library`
  (preferences, caches, containers and the rest). It previously reported only
  the app bundle, so the data it promised to clean stayed on disk.
- `sift-cli uninstall` now lists a LaunchAgent whose `Label` is the app's
  bundle identifier even when the file name differs.
- `sift-cli optimize` and `sift-cli doctor` now report memory in the binary
  units macOS uses, so a 16 GB Mac reads 16 GB instead of 17.2 GB.
- The menu bar popover now quotes disk usage in the same decimal units as the
  Overview. A 245.1 GB disk no longer reads 228.4 GB there.
- `sift-cli` no longer prints a rounded size as "1000 KB" or "1000 MB"; it
  moves up to "1 MB" and "1 GB" like the app does.
- `sift-cli dupes` no longer reports a file as a duplicate when it could not be
  read in full. A failed read used to hash only the bytes read so far, so two
  files that merely shared a prefix could be paired and one listed for removal.
- `sift-cli` now prints an empty size as "0 KB" (as the app does) and a single
  byte as "1 byte" instead of "1 bytes".
- `sift-cli` now keeps its settings and ignore list under the `HOME` it is run
  with (`$HOME/.config/sift`), as the XDG spec defines, instead of always the
  login user's home; `XDG_CONFIG_HOME` still wins when it is an absolute path.
- The selected-count badge in a category keeps four- and five-digit counts on
  one line instead of wrapping into a tall oval.
- Cleaning a category with thousands of rows no longer freezes the window while
  it runs: the visible rows are filtered and sorted once per change instead of
  four times per redraw (largest main-run-loop gap on a 3000-row fixture fell
  from 1.8 s to 218 ms).
- The Overview "Where it sits" bars no longer collapse to a dot at the minimum
  window width; the meter keeps a readable width and the label truncates with
  the full name on hover.
- Counts now agree with their number in every language ("1 item", "2 объекта",
  "5 элементов"); Russian, Ukrainian, Polish and Arabic use their full plural
  rules instead of a single fixed form.
- The same holds for the counts outside the dashboard and file totals: folder
  rows, process rows, schedule runs, battery cycles, the selection bar, the
  removal warnings and the details labels, in all 13 languages. The
  "3 of 1 item" label carries two variables, so each language pluralises the
  number it attaches the noun to.
- The rail now fades the edge that hides rows, so a short window no longer
  looks like the list ends at the last visible item.
- Settings no longer claims every change applies immediately next to a language
  row that needs a restart; the header chip now says "Most changes apply
  immediately".
- Performance no longer prints "service below 80%" under a battery health
  reading that is above 80%; the note appears only when the reading is under
  the threshold, and the caption no longer truncates at the minimum window
  width.

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
