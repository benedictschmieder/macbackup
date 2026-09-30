#!/bin/bash
# macOS preferences: exported preference domains as XML plists.

backup_defaults() {
  info "macOS preferences"
  local dest="$DATA_DIR/defaults" domain file n=0
  fresh_dir "$dest"
  for domain in "${DEFAULTS_DOMAINS[@]}"; do
    file="$dest/$domain.plist"
    if defaults export "$domain" "$file" 2>/dev/null && [ -s "$file" ]; then
      plutil -convert xml1 "$file" >/dev/null 2>&1 || true
      strip_volatile_keys "$domain" "$file"
      n=$((n + 1))
    else
      rm -f "$file"
    fi
  done
  ok "$n domains"
}

strip_volatile_keys() {
  local domain="$1" file="$2" entry key
  for entry in "${DEFAULTS_STRIP_KEYS[@]}"; do
    [ "${entry%%:*}" = "$domain" ] || continue
    key="$(printf '%s' "${entry#*:}" | sed 's/\./\\./g')"
    plutil -remove "$key" "$file" >/dev/null 2>&1 || true
  done
}

restore_defaults() {
  local src="$DATA_DIR/defaults" file domain
  if [ ! -d "$src" ] || [ -z "$(ls "$src" 2>/dev/null)" ]; then warn "No preferences in backup, skipping"; return 0; fi
  info "macOS preferences: $(ls "$src" | grep -c '\.plist$') domains"
  ls "$src" | sed 's/\.plist$//' | sed 's/^/  /'
  log "  Importing replaces the current settings of these domains."
  confirm "Import them?" || return 0
  for file in "$src"/*.plist; do
    domain="$(basename "$file" .plist)"
    run defaults import "$domain" "$file" || warn "could not import $domain"
  done
  run killall Dock 2>/dev/null || true
  run killall Finder 2>/dev/null || true
  run killall SystemUIServer 2>/dev/null || true
  log "  Log out and back in for keyboard, trackpad and input source settings to fully apply."
  return 0
}
