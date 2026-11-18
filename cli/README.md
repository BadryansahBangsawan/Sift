# Sift CLI

Choose what to clean. See where your space goes.

A native Swift command-line companion to [Sift](../README.md) (formerly PureMac), with a keyboard-driven workspace, individual file selection, and an interactive storage explorer. Free, open source, and no telemetry.

![Sift CLI reviewing project artifacts with individual selections and a running size total](screenshots/clean.png)

Captured from the running CLI using sample projects, before the rename to Sift.

## Install

The executable is `sift-cli`, not `sift`, because Homebrew already has an unrelated `sift` formula (a grep alternative) and the two would clash on your `PATH`.

No Sift CLI release is published yet, so [build it from source](#build-from-source) and run `sift-cli`. Once a release exists, publish [`homebrew/sift-cli.rb`](../homebrew/sift-cli.rb) in a tap and install it with `brew install <tap>/sift-cli`.

![Sift CLI workspace with cleanup, storage, and system tools](screenshots/workspace.png)

The release contains a universal binary for Apple Silicon and Intel, signed with Developer ID and submitted to Apple for notarization. Standalone command-line executables cannot carry stapled tickets; the release includes Apple's notarization result.

## Select, review, confirm

Run `sift-cli` to choose a task, or go straight to a scan:

```bash
sift-cli clean dev
sift-cli purge ~/Projects
sift-cli analyze ~/Projects
```

Cleanup opens a selection screen. Nothing is selected when the interactive review begins. Move through the list, choose individual paths, and check the running size total. Press Return to review the selection, then confirm permanent deletion separately.

| Key | Action |
|---|---|
| Up / Down | Move through the results |
| Space | Toggle the focused item |
| A / N | Select matching results / clear the selection |
| / | Search the results |
| Return | Review the selection |
| Esc / Q | Cancel |

Use Left and Right to scroll a long focused path. The final confirmation prints every selected path in full. Selection is by path, including recent project artifacts that earlier versions only displayed.

Prefer an ordinary scrolling terminal? Use `--plain` for numbered selection and a text review:

```bash
sift-cli purge ~/Projects --plain
```

The interface adapts to terminal size. `NO_COLOR` disables color. Redirected output and `TERM=dumb` use plain output.

## Explore storage

`sift-cli analyze` opens a read-only browser sorted by size. Move into a folder with Return or Right, go back with Left or Backspace, and quit with Q. Browsing does not remove anything.

```bash
sift-cli analyze ~/Projects
sift-cli analyze ~/Library --plain --depth 2
sift-cli analyze ~/Projects --json
```

## Commands

| Command | What it does |
|---|---|
| `sift-cli` | Open the interactive workspace |
| `sift-cli clean` | Scan developer caches, user junk, AI-tool caches, and Trash |
| `sift-cli clean dev` | Review package-manager and build-tool caches |
| `sift-cli clean junk` | Review user logs and generated Xcode files |
| `sift-cli clean ai` | Review AI-tool caches and logs |
| `sift-cli clean trash` | Review user and mounted-volume Trash |
| `sift-cli purge [path]` | Find generated artifacts inside project folders |
| `sift-cli analyze [path]` | Browse disk usage without modifying files |
| `sift-cli optimize` | Show factual memory and disk status |
| `sift-cli ignore add <path>` | Protect a path from cleanup |
| `sift-cli ignore remove <path>` | Remove that protection |
| `sift-cli ignore list` | List protected paths |
| `sift-cli doctor` | Report disk, memory, SMART status, launch agents, and Trash size |
| `sift-cli dupes [path]` | Find files with identical contents, read-only |
| `sift-cli uninstall <app>` | Remove an app bundle and the files named after its bundle identifier |
| `sift-cli config` | Show settings and their storage locations |

Run `sift-cli <command> --help` for every option.

## Previews and scripts

`--dry-run` and `--json` never delete files. They do not open the interactive interface, including when combined with `--force`.

```bash
sift-cli clean dev --dry-run
sift-cli purge ~/Projects --json
sift-cli dupes ~/Downloads --json
sift-cli uninstall /Applications/Some.app --dry-run
```

`--force` is an explicit unattended cleanup option. It skips selection and confirmation and permanently removes the scanner's default selection. Preview first. For project artifacts, the default selection uses the age threshold, seven days unless configured otherwise; recent artifacts remain excluded.

```bash
sift-cli purge ~/Projects --older-than 30 --dry-run
sift-cli purge ~/Projects --older-than 30 --force
```

Without `--force`, a noninteractive cleanup does not delete anything.

## What gets scanned

Developer cleanup covers precise cache locations for Homebrew, npm, Yarn, pnpm, pip, Cargo, Go, CocoaPods, Maven, Gradle, Poetry, uv, Bun, Deno, mise, Flutter/Dart, NuGet, Swift Package Manager, Puppeteer and Playwright browser downloads, node-gyp headers, Electron download caches, editor caches, and supported Docker/OrbStack cache paths. It does not invoke a broad Docker prune operation.

Project cleanup finds artifacts such as `node_modules`, `.next`, `.nuxt`, `.turbo`, `.svelte-kit`, `target`, `.build`, `DerivedData`, `Pods`, `.venv`, `__pycache__`, and test/tool caches. Source directories are not artifact targets. Review virtual environments and dependencies before removing them; recreating them may require downloads.

The CLI has its own scan engine and safety checks. Its coverage is separate from the Mac app.

## Cleanup boundaries

- Cleanup is permanent. The selection review lists the exact paths before confirmation.
- Critical filesystem roots, credential/configuration roots, and recognized cloud-provider state are protected.
- Symlink checks and ignore-list checks run again before deletion.
- A path containing an ignored descendant is also protected from removal.
- Failures are reported with paths and a nonzero exit status. Scan sizes are estimates, not a guarantee of a matching increase in available disk space.

Protect a project or folder:

```bash
sift-cli ignore add ~/Projects/important
```

Settings and protected paths live in `~/.config/sift/` (or `$XDG_CONFIG_HOME/sift/`). If that folder has no file yet, the CLI reads the one it used as PureMac, `~/.config/puremac/`, and the next change saves to the new folder. The old file is left as it was.

Sift does not claim to boost RAM or reliably reclaim APFS purgeable space. macOS manages both; `optimize` reports their state without forcing cleanup.

## Build from source

Requires macOS 11 or later and a Swift 5.9+ toolchain.

```bash
cd cli
swift test
swift build -c release
.build/release/sift-cli
```

See [the local release script](../scripts/release-cli-local.sh) for universal builds, signing, and Apple notarization. Publishing also requires updating the Homebrew formula to the checksum of the released archive.
