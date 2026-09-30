# Mac backup

Software and configuration of a Mac, collected by [macbackup](https://github.com/benedictschmieder/macbackup). User files are not included. The tool refuses to commit when it finds something that looks like a secret.

## Layout

- `Brewfile`: taps, formulae installed on request, casks and App Store apps. Homebrew installs the dependencies.
- `brew/`: full formula list including dependencies, for reference only.
- `dotfiles/`: copies of the configured files under the home directory, same relative paths.
- `vscode/`: VS Code settings, keybindings, snippets, MCP config and extension list.
- `defaults/`: exported macOS preference domains (one XML plist per domain).
- `launchagents/`: user LaunchAgents and the list of login items.
- `system/`: macOS version, hardware and the applications present, for reference only.
- `macbackup.conf`: what gets backed up. Edit this to add or remove items.

## Restore on a new Mac

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/benedictschmieder/macbackup/main/install.sh)"
macbackup init
macbackup restore
```
