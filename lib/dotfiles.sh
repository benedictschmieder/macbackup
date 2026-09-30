#!/bin/bash
# Dotfiles: copies of the configured files and directories under $HOME.

backup_dotfiles() {
  info "Dotfiles"
  local dest="$DATA_DIR/dotfiles" item parent n=0
  local excludes=()
  local p
  for p in "${EXCLUDE_PATTERNS[@]}"; do excludes+=(--exclude "$p"); done
  fresh_dir "$dest"
  local items=("${DOTFILES[@]}")
  if [ "${DOTFILES_AUTO_CONFIG:-0}" = 1 ]; then items+=(.config); fi
  for item in "${items[@]}"; do
    item="${item%/}"
    [ -e "$HOME/$item" ] || continue
    parent="$dest/$(dirname "$item")"
    mkdir -p "$parent"
    rsync -aL --max-size="${DOTFILES_MAX_SIZE_KB:-1024}k" "${excludes[@]}" "$HOME/$item" "$parent/"
    n=$((n + 1))
  done
  ok "$n entries, $(count_files "$dest") files"
}

restore_dotfiles() {
  local src="$DATA_DIR/dotfiles"
  if [ ! -d "$src" ]; then warn "No dotfiles in backup, skipping"; return 0; fi
  info "Dotfiles: $(count_files "$src") files"
  confirm "Copy them into $HOME? (files that differ are first saved to $RESTORE_BACKUP_DIR)" || return 0
  restore_tree "$src" "$HOME"
  if [ -d "$HOME/.ssh" ]; then run chmod 700 "$HOME/.ssh"; fi
  return 0
}

restore_tree() {
  # restore_tree <source dir> <target dir>
  local rel
  (cd "$1" && find . -type f -print) | sed 's|^\./||' | while IFS= read -r rel; do
    restore_file "$1/$rel" "$2/$rel"
  done
}

restore_file() {
  # restore_file <source> <destination>; keeps a copy of a differing destination.
  local src="$1" dest="$2" rel="${2#"$HOME"/}"
  if [ -e "$dest" ] && cmp -s "$src" "$dest"; then return 0; fi
  if [ -e "$dest" ]; then
    run mkdir -p "$RESTORE_BACKUP_DIR/$(dirname "$rel")"
    run cp -p "$dest" "$RESTORE_BACKUP_DIR/$rel"
  fi
  run mkdir -p "$(dirname "$dest")"
  run cp -p "$src" "$dest"
  [ "$DRY_RUN" = 1 ] || log "  restored $rel"
}
