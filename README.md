# recent-work

A lightweight macOS daemon that watches your project directories for file changes and maintains `~/RecentWork/` as a flat folder of symlinks to recently modified files.

Built for fast AI-assisted development workflows — grab the files you need from one place instead of hunting through Finder. Think of it as macOS Recents, but actually useful.

> **Requirements:** macOS 13+ · Swift 5.9

## Install

**Homebrew:**

    brew install jadnohra/tap/recent-work

**Quick install:**

    curl -fsSL https://raw.githubusercontent.com/jadnohra/recent-work/main/install.sh | sh

**Build from source:**

    swift build -c release
    cp .build/release/recent-work /usr/local/bin/

## Quick Start

```sh
recent-work init      # set up launchd service
recent-work start     # start the daemon
```

That's it. `~/RecentWork/` will start populating as you edit files.

## Commands

|Command|Description|
|---|---|
|`recent-work init`|Install the launchd service|
|`recent-work start`|Start the daemon|
|`recent-work start --foreground`|Run in foreground (useful for debugging)|
|`recent-work stop`|Stop the daemon|
|`recent-work status`|Show current state|
|`recent-work list`|List tracked files|
|`recent-work clear [--yes]`|Remove all symlinks|
|`recent-work uninstall [--yes]`|Uninstall completely|

## How It Works

- **Watches** common project directories under `~/` via FSEvents
- **Creates symlinks** in `~/RecentWork/` pointing to recently modified files
- **Resolves name collisions** by prefixing the parent directory, falling back to a hash suffix
- **Prunes automatically** every 60s — max 100 symlinks, 48h max age, broken symlinks cleaned up on the fly
- **Ignores noise** — hidden files/directories, build artifacts (`.o`, `.tmp`, `.pyc`), lockfiles, binaries, archives, etc.

Runs as a launchd service (`com.recentwork.daemon`). Starts on login, restarts on crash.

## recent-work Pro

Custom watch rules, cross-platform support, and a native installer.
Check out [recent-work Pro](https://recent-work.com).

## License

MIT