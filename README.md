# macbackup

Backs up the software and configuration of a Mac to a private GitHub repository, and restores it on a new one. Homebrew is the source of truth for software: only the formulae you installed yourself, the casks and the App Store apps are recorded, and Homebrew resolves the dependencies again on the new machine. User files are not touched; they belong in cloud storage.

## What is backed up

| Module | Content | Restore |
| --- | --- | --- |
| `brew` | `Brewfile` with taps, formulae installed on request, casks and `mas` apps | `brew bundle install` |
| `dotfiles` | Shell, git, ssh config, Claude Code and Claude Desktop settings, all of `~/.config`, Quick Actions, custom dictionary, Docker, Bambu Studio and Obsidian settings | Copied back, replaced files are saved first |
| `vscode` | VS Code `settings.json`, `keybindings.json`, snippets, `mcp.json`, extension list | Copied back, extensions installed via `code` |
| `defaults` | Exported macOS preference domains: system settings plus the preferences of every installed app, found by bundle identifier | `defaults import` |
| `launchagents` | User LaunchAgents and login items | Copied back and loaded, login items re-added |
| `system` | macOS version, hardware, list of installed applications | Reference only |

New apps and tools are picked up without configuration: the Brewfile follows Homebrew, app preferences are found by bundle identifier, extensions and login items are listed live, and `~/.config` is copied as a whole. Exports larger than a size cap are skipped as state rather than settings.

Every run is scanned for secrets (GitHub, OpenAI, AWS, Slack, Google tokens, private keys, JWTs, generic `token=`/`password=` assignments) before anything is committed. License, password or token keys inside exported preferences are removed automatically and reported. A hit in a text file aborts the backup and shows the file and line. Known secret-holding files such as `~/.config/gh/hosts.yml`, `known_hosts`, keys and certificates are excluded up front, and volatile keys are stripped from exported preferences.

## Install

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/benedictschmieder/macbackup/main/install.sh)"
```

The installer adds Homebrew and the GitHub CLI if they are missing, clones this repository to `~/.macbackup` and links `macbackup` into Homebrew's `bin`.

## Set up on the Mac to back up

```sh
macbackup init      # logs in to GitHub, creates the private repo <you>/macbackup-data, installs the daily schedule
macbackup backup    # first backup
```

The backup runs daily via launchd (12:00 by default, missed runs happen after wake-up) and only pushes when something changed. The schedule runs through a small launcher binary in `~/.macbackup/libexec` rather than through `/bin/bash` directly, which lets it read the preferences of sandboxed apps (Maccy, Shottr, TextEdit and similar). Should `macbackup schedule status` ever report domains the scheduled run could not read, the run keeps their last export, and `macbackup schedule access` explains how to grant Full Disk Access to the launcher alone. Failures show up as a macOS notification and in `~/Library/Logs/macbackup/backup.log`.

## Restore on a new Mac

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/benedictschmieder/macbackup/main/install.sh)"
macbackup init      # logs in to GitHub and clones the existing backup
macbackup restore   # installs the Brewfile, then dotfiles, VS Code, preferences, LaunchAgents and login items
```

Each restore step asks for confirmation. Use `--only brew,dotfiles` to run a subset, `--dry-run` to see what would happen, and `--yes` to skip the prompts. Files that would be replaced are saved to `~/.macbackup-restore-<timestamp>` first. Sign in to the App Store before restoring if the Brewfile contains `mas` entries. Log out and back in afterwards for keyboard and trackpad preferences to apply fully.

`macbackup backup` refuses to overwrite a backup with one that has less than half as many Homebrew entries, which protects the backup from a freshly set up Mac that has not been restored yet. Use `--force` when the shrink is intended.

## Several Macs

Use one backup repository per Mac. Point each machine at its own repo during setup:

```sh
macbackup init --repo <you>/macbackup-<machine name>
```

A new Mac restores from whichever repo you name in `macbackup init`. Each repository records which Mac it belongs to in `.macbackup-host`. A different Mac that runs `macbackup backup` against it is refused, with the two ways out spelled out: `macbackup init --repo` for a separate backup, or `macbackup restore` (or `backup --force`) to take the backup over, which is the normal path for a replacement machine.

## Configure what is backed up

The settings live in the backup repository as `macbackup.conf`, so every Mac restored from it keeps the same settings. The file is plain bash:

- `DOTFILES_AUTO_CONFIG`, `DOTFILES_MAX_SIZE_KB`: copy all of `~/.config`, skipping large files
- `DOTFILES`: files and directories relative to `$HOME`
- `EXCLUDE_PATTERNS`: names never copied (rsync exclude syntax)
- `DEFAULTS_AUTO_APPS`, `DEFAULTS_APP_DIRS`, `DEFAULTS_EXCLUDE_DOMAINS`, `DEFAULTS_MAX_SIZE_KB`: automatic export of installed apps' preferences
- `DEFAULTS_DOMAINS`: preference domains always exported (`defaults domains | tr ',' '\n'` lists what exists)
- `DEFAULTS_STRIP_KEYS`: `domain:key` entries removed from exports, for volatile values and license keys
- `DEFAULTS_STRIP_KEY_PATTERNS`: regular expressions for top-level keys removed from every domain (window positions, telemetry)
- `SECRET_ALLOWLIST`: regular expressions for confirmed false positives of the secret scanner
- `MODULES`, `BACKUP_HOUR`, `BACKUP_MINUTE`, `VSCODE_USER_DIR`

The defaults are in [`share/macbackup.conf`](share/macbackup.conf). Changes are committed with the next backup.

## Commands

```
macbackup init [--repo owner/name] [--data-dir path] [--no-schedule] [--yes]
macbackup backup [--only modules] [--no-push] [--dry-run] [--force]
macbackup restore [--only modules] [--dry-run] [--yes]
macbackup status
macbackup schedule install|remove|status|run|access
macbackup doctor
macbackup update
```

## Uninstall

```sh
~/.macbackup/uninstall.sh            # removes the tool and schedule, keeps config and local checkout
~/.macbackup/uninstall.sh --purge    # also removes config and the local checkout (the GitHub repo stays)
```

## Layout

```
bin/macbackup         entry point
lib/*.sh              one file per module plus backup, restore, init, schedule, secrets
share/macbackup.conf  default settings, copied into the backup repository on init
share/data-readme.md  README written into the backup repository
install.sh            one-line installer
uninstall.sh
```

Requires macOS with the stock `/bin/bash` 3.2; no other runtime.
