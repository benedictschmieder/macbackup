#!/bin/bash
# macOS preferences: exported preference domains as XML plists.

backup_defaults() {
  info "macOS preferences"
  local dest="$DATA_DIR/defaults" prev domain file n=0 kept="" skipped="" stripped=""
  prev="$(mktemp -d)"
  if [ -d "$dest" ]; then cp -R "$dest"/. "$prev"/; fi
  fresh_dir "$dest"
  for domain in $(collect_domains); do
    file="$dest/$domain.plist"
    if ! defaults export "$domain" "$file" 2>/dev/null || [ ! -s "$file" ]; then
      rm -f "$file"
      continue
    fi
    plutil -convert xml1 "$file" >/dev/null 2>&1 || true
    if ! plist_has_keys "$file"; then
      # Sandboxed apps' domains read as empty without Full Disk Access; keep the last good export.
      if [ -f "$prev/$domain.plist" ] && plist_has_keys "$prev/$domain.plist"; then
        cp -p "$prev/$domain.plist" "$file"
        kept="$kept $domain"
      else
        rm -f "$file"
        continue
      fi
    else
      if [ "$(( $(stat -f %z "$file") / 1024 ))" -gt "${DEFAULTS_MAX_SIZE_KB:-256}" ]; then
        rm -f "$file"
        skipped="$skipped $domain"
        continue
      fi
      strip_volatile_keys "$domain" "$file"
      stripped="$stripped$(strip_secret_keys "$domain" "$file")"
      # A domain that only held volatile keys is not worth keeping.
      if ! plist_has_keys "$file"; then rm -f "$file"; continue; fi
    fi
    n=$((n + 1))
  done
  rm -rf "$prev"
  ok "$n domains"
  record_state unreadable_domains "$kept"
  [ -z "$kept" ] || log "  not readable here, kept previous export:$kept"
  [ -z "$skipped" ] || log "  skipped, larger than ${DEFAULTS_MAX_SIZE_KB:-256} KB (state, not settings):$skipped"
  [ -z "$stripped" ] || log "  removed secret-looking keys:$stripped"
}

collect_domains() {
  # Configured domains plus, when enabled, the bundle identifier of every installed app.
  {
    printf '%s\n' "${DEFAULTS_DOMAINS[@]}"
    if [ "${DEFAULTS_AUTO_APPS:-0}" = 1 ]; then installed_app_domains; fi
  } | grep -v '^$' | sort -u | grep -Fvx -f <(printf '%s\n' "${DEFAULTS_EXCLUDE_DOMAINS[@]}" | grep -v '^$') || true
}

installed_app_domains() {
  local dir app
  for dir in "${DEFAULTS_APP_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 2 -name '*.app' -print 2>/dev/null | while IFS= read -r app; do
      /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true
    done
  done
}

plist_has_keys() { grep -q '<key>' "$1" 2>/dev/null; }

plist_top_level_keys() {
  # Top-level keys sit at exactly one tab of indentation in plutil's xml1 output.
  sed -n 's/^	<key>\(.*\)<\/key>$/\1/p' "$1" | plist_unescape
}

plist_unescape() { sed 's/&amp;/\&/g;s/&lt;/</g;s/&gt;/>/g'; }

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

strip_secret_keys() {
  # Removes the top-level key holding any secret-looking value; prints " domain:key" per removal.
  local domain="$1" file="$2" key
  plist_secret_top_keys "$file" | sort -u | while IFS= read -r key; do
    [ -n "$key" ] || continue
    plist_remove_key "$file" "$key"
    printf ' %s:%s' "$domain" "$key"
  done
}

plist_secret_top_keys() {
  # Top-level key under which a secret-looking key with a non-empty string or data value appears.
  awk -v re="$PLIST_SECRET_KEY_REGEX" '
    /^\t<key>/ { top = $0; sub(/^\t<key>/, "", top); sub(/<\/key>$/, "", top) }
    /<key>/ { flag = (tolower($0) ~ re) ? FNR : 0; next }
    flag && FNR == flag + 1 && $0 ~ /<(string|data)>[^<]+</ { print top }
  ' "$1" | plist_unescape
}

restore_defaults() {
  local src="$DATA_DIR/defaults" file domain
  if [ ! -d "$src" ] || [ -z "$(ls "$src" 2>/dev/null)" ]; then warn "No preferences in backup, skipping"; return 0; fi
  info "macOS preferences: $(count_matching "$src" '*.plist') domains"
  list_basenames "$src" '*.plist' | sed 's/\.plist$//' | sed 's/^/  /'
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
