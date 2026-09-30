#!/bin/bash
# VS Code: user settings, keybindings, snippets, MCP config and the extension list.

VSCODE_FILES="settings.json keybindings.json mcp.json"

backup_vscode() {
  info "VS Code"
  local dest="$DATA_DIR/vscode" f
  if [ ! -d "$VSCODE_USER_DIR" ]; then log "  not installed, skipping"; return 0; fi
  fresh_dir "$dest"
  for f in $VSCODE_FILES; do
    [ -f "$VSCODE_USER_DIR/$f" ] && cp -p "$VSCODE_USER_DIR/$f" "$dest/$f"
  done
  if [ -d "$VSCODE_USER_DIR/snippets" ]; then
    rsync -aL --exclude .DS_Store "$VSCODE_USER_DIR/snippets" "$dest/"
  fi
  if command -v code >/dev/null 2>&1; then
    code --list-extensions 2>/dev/null | sort > "$dest/extensions.txt" || true
  else
    warn "'code' command not found; extension list not backed up"
  fi
  ok "$(count_files "$dest") files, $(grep -c . "$dest/extensions.txt" 2>/dev/null || echo 0) extensions"
}

restore_vscode() {
  local src="$DATA_DIR/vscode" f ext
  if [ ! -d "$src" ]; then warn "No VS Code data in backup, skipping"; return 0; fi
  info "VS Code: $(count_files "$src") files, $(grep -c . "$src/extensions.txt" 2>/dev/null || echo 0) extensions"
  confirm "Restore VS Code settings and install the extensions?" || return 0
  for f in $VSCODE_FILES; do
    [ -f "$src/$f" ] && restore_file "$src/$f" "$VSCODE_USER_DIR/$f"
  done
  [ -d "$src/snippets" ] && restore_tree "$src/snippets" "$VSCODE_USER_DIR/snippets"
  if [ -f "$src/extensions.txt" ]; then
    if command -v code >/dev/null 2>&1; then
      while IFS= read -r ext; do
        [ -n "$ext" ] || continue
        run code --install-extension "$ext" >/dev/null 2>&1 || warn "could not install extension $ext"
      done < "$src/extensions.txt"
      [ "$DRY_RUN" = 1 ] || ok "extensions installed"
    else
      warn "'code' command not found. Install VS Code first (brew module), then re-run 'macbackup restore --only vscode'."
    fi
  fi
  return 0
}
