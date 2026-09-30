#!/bin/bash
# Removes macbackup. Keeps the backup checkout and configuration unless --purge is given.
set -eo pipefail

MACBACKUP_HOME="${MACBACKUP_HOME:-$HOME/.macbackup}"
config="${XDG_CONFIG_HOME:-$HOME/.config}/macbackup"

launchctl bootout "gui/$(id -u)/dev.macbackup.backup" >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/dev.macbackup.backup.plist"
if command -v brew >/dev/null 2>&1; then rm -f "$(brew --prefix)/bin/macbackup"; fi
rm -rf "$MACBACKUP_HOME" "$HOME/Library/Logs/macbackup" "${XDG_STATE_HOME:-$HOME/.local/state}/macbackup"
echo "macbackup removed."

if [ "${1:-}" = "--purge" ]; then
  data_dir="$(sed -n 's/^DATA_DIR=//p' "$config/config" 2>/dev/null | tr -d "'\"")"
  rm -rf "$config"
  [ -n "$data_dir" ] && rm -rf "${data_dir/#\~/$HOME}"
  echo "Configuration and local backup checkout removed. The GitHub repository was left untouched."
else
  echo "Configuration in $config and the local backup checkout were kept. Use --purge to remove them too."
fi
