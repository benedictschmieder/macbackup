#!/bin/bash
# macOS preferences: exported preference domains as XML plists.

backup_defaults() {
  info "macOS preferences"
  local dest="$DATA_DIR/defaults" prev domain file n=0 kept=""
  prev="$(mktemp -d)"
  if [ -d "$dest" ]; then cp -R "$dest"/. "$prev"/; fi
  fresh_dir "$dest"
  for domain in "${DEFAULTS_DOMAINS[@]}"; do
    file="$dest/$domain.plist"
    if ! defaults export "$domain" "$file" 2>/dev/null || [ ! -s "$file" ]; then
      rm -f "$file"
      continue
    fi
    plutil -convert xml1 "$file" >/dev/null 2>&1 || true
    if ! plist_has_keys "$file"; then
      # Sandboxed apps' domains read as empty without Full Disk Access (e.g. from launchd); keep the last good export.
      if [ -f "$prev/$domain.plist" ] && plist_has_keys "$prev/$domain.plist"; then
        cp -p "$prev/$domain.plist" "$file"
        kept="$kept $domain"
      else
        rm -f "$file"
        continue
      fi
    else
      strip_volatile_keys "$domain" "$file"
      # A domain that only held volatile keys is not worth keeping.
      if ! plist_has_keys "$file"; then rm -f "$file"; continue; fi
    fi
    n=$((n + 1))
  done
  rm -rf "$prev"
  ok "$n domains"
  [ -z "$kept" ] || log "  not readable here, kept previous export:$kept"
}

plist_has_keys() { grep -q '<key>' "$1" 2>/dev/null; }

plist_top_level_keys() {
  # Top-level keys sit at exactly one tab of indentation in plutil's xml1 output.
  sed -n 's/^	<key>\(.*\)<\/key>$/\1/p' "$1" | sed 's/&amp;/\&/g;s/&lt;/</g;s/&gt;/>/g'
}

plist_remove_key() {
  # plutil uses '.' as a key path separator, so dots inside key names are escaped.
  plutil -remove "$(printf '%s' "$2" | sed 's/\./\\./g')" "$1" >/dev/null 2>&1 || true
}

strip_volatile_keys() {
  local domain="$1" file="$2" entry key pattern
  for entry in "${DEFAULTS_STRIP_KEYS[@]}"; do
    case "${entry%%:*}" in "$domain"|'*') plist_remove_key "$file" "${entry#*:}" ;; esac
  done
  [ "${#DEFAULTS_STRIP_KEY_PATTERNS[@]}" -gt 0 ] || return 0
  plist_top_level_keys "$file" | while IFS= read -r key; do
    for pattern in "${DEFAULTS_STRIP_KEY_PATTERNS[@]}"; do
      if printf '%s\n' "$key" | grep -Eq "$pattern"; then plist_remove_key "$file" "$key"; break; fi
    done
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
