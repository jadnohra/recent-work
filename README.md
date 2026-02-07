# recent-work

**Stop wasting time finding your recent files.**

A lightweight macOS daemon that watches your project directories for file changes and maintains `~/RecentWork/` as a flat folder of symlinks to recently modified files.

- **AI workflows** — grab the files you need from one place instead of hunting through Finder when feeding context to Claude, Cursor, etc.
- **General productivity** — macOS has a built-in Recents view in Finder, the system file manager. It's a good idea, but it only tracks files opened through Finder itself. Anything touched by an editor, terminal, CLI tool, or AI agent is invisible to it. This watches the filesystem directly, so nothing gets missed.

> **Requirements:** macOS 13+ · Swift 5.9

## Install

### Homebrew (recommended)

```sh
brew install jadnohra/tap/recent-work
```

### Quick install

```sh
curl -fsSL https://raw.githubusercontent.com/jadnohra/recent-work/main/install.sh | sh
```

### Build from source

```sh
swift build -c release
cp .build/release/recent-work /usr/local/bin/
```

## Quick Start

```sh
recent-work init      # set up launchd service
recent-work start     # start the daemon
```

That's it. `~/RecentWork/` will start populating as you edit files.

## Commands

| Command | Description |
|---|---|
| `recent-work init` | Install the launchd service |
| `recent-work start` | Start the daemon |
| `recent-work start --foreground` | Run in foreground (useful for debugging) |
| `recent-work stop` | Stop the daemon |
| `recent-work status` | Show current state |
| `recent-work list` | List tracked files |
| `recent-work clear [--yes]` | Remove all symlinks |
| `recent-work uninstall [--yes]` | Uninstall completely |

## How It Works

- **Watches** common project directories under `~/` via FSEvents
- **Creates symlinks** in `~/RecentWork/` pointing to recently modified files
- **Resolves name collisions** by prefixing the parent directory, falling back to a hash suffix
- **Prunes automatically** every 60s — max 100 symlinks, 48h max age, broken symlinks cleaned up on the fly
- **Ignores noise** — hidden files/directories, build artifacts (`.o`, `.tmp`, `.pyc`), lockfiles, binaries, archives, etc.

Runs as a launchd service (`com.recentwork.daemon`). Starts on login, restarts on crash.

## Recent Work Pro

Custom watch rules, cross-platform support, and a native installer. Check out [**Recent Work Pro**](https://recent-work.com).

## License

MIT