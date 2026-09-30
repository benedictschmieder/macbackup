#!/bin/bash
# User LaunchAgents and login items.

backup_launchagents() {
  info "LaunchAgents and login items"
  local dest="$DATA_DIR/launchagents" f items
  fresh_dir "$dest"
  for f in "$HOME"/Library/LaunchAgents/*.plist; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "$LAUNCHD_LABEL.plist" ] && continue
    cp -p "$f" "$dest/"
    plutil -convert xml1 "$dest/$(basename "$f")" >/dev/null 2>&1 || true
  done
  items="$(list_login_items || true)"
  if [ -n "$items" ]; then printf '%s\n' "$items" > "$dest/login-items.tsv"; fi
  ok "$(count_matching "$dest" '*.plist') agents, $(printf '%s\n' "$items" | grep -c .) login items"
}

list_login_items() {
  osascript 2>/dev/null <<'APPLESCRIPT'
set out to ""
tell application "System Events"
  repeat with li in login items
    set out to out & (name of li) & tab & (path of li) & linefeed
  end repeat
end tell
return out
APPLESCRIPT
}

restore_launchagents() {
  local src="$DATA_DIR/launchagents" f name path
  if [ ! -d "$src" ]; then warn "No LaunchAgents in backup, skipping"; return 0; fi
  if ls "$src"/*.plist >/dev/null 2>&1; then
    info "LaunchAgents: $(count_matching "$src" '*.plist')"
    list_basenames "$src" '*.plist' | sed 's/^/  /'
    log "  Agents installed by apps are recreated by the apps themselves; restore only custom ones if unsure."
    if confirm "Restore these LaunchAgents?"; then
      for f in "$src"/*.plist; do
        restore_file "$f" "$HOME/Library/LaunchAgents/$(basename "$f")"
        run launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$(basename "$f")" 2>/dev/null || true
      done
    fi
  fi
  if [ -f "$src/login-items.tsv" ]; then
    info "Login items: $(grep -c . "$src/login-items.tsv")"
    cut -f1 "$src/login-items.tsv" | sed 's/^/  /'
    if confirm "Re-add the login items whose apps are installed?"; then
      while IFS=$'\t' read -r name path; do
        [ -n "$path" ] || continue
        if [ -e "$path" ]; then
          if run osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$path\", hidden:false}" >/dev/null 2>&1; then
            log "  added $name"
          else
            warn "could not add login item $name"
          fi
        else
          warn "skipping login item $name: $path not found"
        fi
      done < "$src/login-items.tsv"
    fi
  fi
  return 0
}
