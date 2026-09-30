#!/bin/bash
# Secret scanner run over the collected backup before anything is committed.

# Case-sensitive token formats.
SECRET_PATTERNS_CS='gh[pousr]_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{20,}
sk-(ant-)?[A-Za-z0-9_-]{20,}
AKIA[0-9A-Z]{16}
xox[baprs]-[A-Za-z0-9-]{10,}
AIza[0-9A-Za-z_-]{35}
glpat-[A-Za-z0-9_-]{20,}
-----BEGIN [A-Z ]*PRIVATE KEY-----
eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}'

# Case-insensitive "key = value" assignments with a secret-looking key.
SECRET_PATTERNS_CI='(api[_-]?key|secret|passw(or)?d|token|client[_-]?secret|private[_-]?key)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_./+=-]{12,}'

scan_secrets() {
  # scan_secrets <dir>; prints findings and returns 1 when any remain after the allowlist.
  local dir="$1" findings tmp
  tmp="$(mktemp)"
  {
    grep -rIEn --exclude-dir=.git "$SECRET_PATTERNS_CS" "$dir" 2>/dev/null || true
    grep -rIEin --exclude-dir=.git "$SECRET_PATTERNS_CI" "$dir" 2>/dev/null || true
    scan_plists "$dir"
  } | sort -u > "$tmp"

  findings="$(apply_allowlist "$tmp")"
  rm -f "$tmp"
  [ -z "$findings" ] && return 0

  printf '%sSecrets detected in the collected backup:%s\n' "$C_RED" "$C_RESET" >&2
  printf '%s\n' "$findings" | sed "s|^$dir/|  |" | cut -c1-200 >&2
  cat >&2 <<MSG

Nothing was committed. Fix it in $DATA_DIR/macbackup.conf:
  - a file: remove it from DOTFILES or add its name to EXCLUDE_PATTERNS
  - a preference key: add domain:key to DEFAULTS_STRIP_KEYS (or drop the domain from DEFAULTS_DOMAINS)
  - a false positive: add a matching regular expression to SECRET_ALLOWLIST
MSG
  return 1
}

apply_allowlist() {
  local file="$1" pattern
  if [ "${#SECRET_ALLOWLIST[@]}" -eq 0 ]; then cat "$file"; return 0; fi
  local filtered
  filtered="$(cat "$file")"
  for pattern in "${SECRET_ALLOWLIST[@]}"; do
    [ -n "$pattern" ] || continue
    filtered="$(printf '%s\n' "$filtered" | grep -Ev "$pattern" || true)"
  done
  printf '%s' "$filtered"
}

scan_plists() {
  # Flags plist keys with secret-looking names whose value is a non-empty string or data.
  find "$1" -name '*.plist' -not -path '*/.git/*' -print0 2>/dev/null | xargs -0 awk '
    /<key>/ {
      k = tolower($0)
      if (k ~ /(serial|licen[cs]e|passw|token|secret|apikey|api_key|private_key|credential)/) { flag = FNR } else { flag = 0 }
      next
    }
    flag && FNR == flag + 1 && $0 ~ /<(string|data)>[^<]+</ { print FILENAME ":" FNR ":" $0 }
  ' 2>/dev/null || true
}
