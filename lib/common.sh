#!/bin/bash
# Shared helpers: output, configuration, prompts, dry-run wrapper.

MACBACKUP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/macbackup"
MACBACKUP_CONFIG="$MACBACKUP_CONFIG_DIR/config"
MACBACKUP_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/macbackup"
MACBACKUP_LOG_DIR="$HOME/Library/Logs/macbackup"
MACBACKUP_ALL_MODULES="brew dotfiles vscode defaults launchagents system"

DRY_RUN=0
ASSUME_YES=0
ONLY_MODULES=""

if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_RESET=$'\033[0m'
else
  C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_RESET=""
fi

log()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%sWarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sError:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# Runs the command, or only prints it when --dry-run is active.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s  [dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
    return 0
  fi
  "$@"
}

confirm() {
  if [ "$ASSUME_YES" = 1 ] || [ "$DRY_RUN" = 1 ]; then return 0; fi
  if [ ! -t 0 ]; then
    warn "No terminal available to confirm: $1 (skipped; use --yes to skip prompts)"
    return 1
  fi
  printf '%s [y/N] ' "$1"
  read -r answer
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_default() {
  # prompt_default <question> <default> -> prints the answer
  local answer
  if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then
    printf '%s' "$2"
    return 0
  fi
  printf '%s [%s]: ' "$1" "$2" >&2
  read -r answer
  printf '%s' "${answer:-$2}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed. $2"
}

notify() {
  # notify <subtitle> <message>; a macOS notification for unattended runs.
  osascript -e "display notification \"$2\" with title \"macbackup\" subtitle \"$1\"" >/dev/null 2>&1 || true
}

load_local_config() {
  [ -f "$MACBACKUP_CONFIG" ] || die "macbackup is not configured on this Mac. Run 'macbackup init' first."
  # shellcheck source=/dev/null
  . "$MACBACKUP_CONFIG"
  [ -n "$DATA_REPO" ] && [ -n "$DATA_DIR" ] || die "$MACBACKUP_CONFIG is incomplete. Run 'macbackup init' again."
}

load_config() {
  load_local_config
  # shellcheck source=share/macbackup.conf
  . "$MACBACKUP_ROOT/share/macbackup.conf"
  if [ -f "$DATA_DIR/macbackup.conf" ]; then
    # shellcheck source=/dev/null
    . "$DATA_DIR/macbackup.conf"
  fi
  validate_modules "$MODULES"
}

validate_modules() {
  local m
  for m in $(printf '%s' "$1" | tr ',' ' '); do
    case " $MACBACKUP_ALL_MODULES " in
      *" $m "*) ;;
      *) die "Unknown module '$m'. Available: $MACBACKUP_ALL_MODULES" ;;
    esac
  done
}

module_enabled() {
  case " $MODULES " in *" $1 "*) ;; *) return 1 ;; esac
  [ -z "$ONLY_MODULES" ] && return 0
  case ",$ONLY_MODULES," in *",$1,"*) return 0 ;; esac
  return 1
}

data_git() { git -C "$DATA_DIR" "$@"; }

ensure_data_repo() {
  [ -d "$DATA_DIR/.git" ] || die "Backup directory $DATA_DIR is not a git repository. Run 'macbackup init'."
}

fresh_dir() { rm -rf "$1"; mkdir -p "$1"; }

count_files() { find "$1" -type f 2>/dev/null | wc -l | tr -d ' '; }

timestamp() { date +%Y-%m-%dT%H:%M:%S%z; }

record_state() {
  # record_state <key> <value>; small key=value file describing the last run.
  mkdir -p "$MACBACKUP_STATE_DIR"
  local file="$MACBACKUP_STATE_DIR/last-run" tmp
  tmp="$(mktemp)"
  if [ -f "$file" ]; then grep -v "^$1=" "$file" > "$tmp" || true; fi
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  mv "$tmp" "$file"
}

read_state() {
  [ -f "$MACBACKUP_STATE_DIR/last-run" ] || return 0
  sed -n "s/^$1=//p" "$MACBACKUP_STATE_DIR/last-run"
}
