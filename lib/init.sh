#!/bin/bash
# The init command: GitHub login, backup repository, local configuration.

cmd_init() {
  local repo="" dir="" schedule=1
  # shellcheck disable=SC2034
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo="$2"; shift ;;
      --repo=*) repo="${1#--repo=}" ;;
      --data-dir) dir="$2"; shift ;;
      --data-dir=*) dir="${1#--data-dir=}" ;;
      --no-schedule) schedule=0 ;;
      --yes|-y) ASSUME_YES=1 ;;
      -h|--help) usage_init; return 0 ;;
      *) die "Unknown option for init: $1 (see 'macbackup init --help')" ;;
    esac
    shift
  done
  require_cmd brew "Install it from https://brew.sh or re-run the macbackup installer."
  require_cmd git "Install the Xcode command line tools: xcode-select --install"
  require_cmd gh "Install it with: brew install gh"

  if ! gh auth status >/dev/null 2>&1; then
    info "GitHub login"
    gh auth login --hostname github.com --git-protocol https --web
  fi
  local login
  login="$(gh api user -q .login)"
  ok "logged in to GitHub as $login"

  if [ -f "$MACBACKUP_CONFIG" ]; then
    # shellcheck source=/dev/null
    . "$MACBACKUP_CONFIG"
  fi
  [ -n "$repo" ] || repo="$(prompt_default "Backup repository (private)" "${DATA_REPO:-$login/macbackup-data}")"
  [ -n "$dir" ] || dir="$(prompt_default "Local checkout directory" "${DATA_DIR:-$HOME/.macbackup-data}")"
  case "$repo" in */*) ;; *) repo="$login/$repo" ;; esac
  dir="${dir/#\~/$HOME}"

  ensure_remote_repo "$repo"
  ensure_local_clone "$repo" "$dir"

  mkdir -p "$MACBACKUP_CONFIG_DIR"
  printf 'DATA_REPO=%q\nDATA_DIR=%q\n' "$repo" "$dir" > "$MACBACKUP_CONFIG"
  ok "configuration written to $MACBACKUP_CONFIG"
  DATA_REPO="$repo"; DATA_DIR="$dir"

  if [ -f "$dir/Brewfile" ]; then
    local owner
    owner="$(backup_owner)"
    info "The repository already contains a backup${owner:+ of $owner}"
    log "  Run 'macbackup restore' to apply it to this Mac, which then owns the backup."
    log "  Run 'macbackup backup --force' instead if this Mac should overwrite it without restoring."
    if [ -n "$owner" ] && [ "$owner" != "$(this_host)" ]; then
      log "  For a separate backup of this Mac, re-run: macbackup init --repo $login/macbackup-<name>"
    fi
    log "  The daily schedule is installed after a restore, or with 'macbackup schedule install'."
  else
    if [ "$schedule" = 1 ]; then load_config; schedule_install; fi
    info "Ready. Run 'macbackup backup' to create the first backup."
    log "  Adjust what gets backed up in $dir/macbackup.conf"
  fi
}

ensure_remote_repo() {
  local repo="$1" visibility
  if gh repo view "$repo" --json name >/dev/null 2>&1; then
    ok "using existing repository $repo"
  else
    info "Creating private repository $repo"
    gh repo create "$repo" --private --description "macOS software and configuration backup, managed by macbackup" >/dev/null
    ok "created"
  fi
  visibility="$(gh repo view "$repo" --json visibility -q .visibility 2>/dev/null || echo UNKNOWN)"
  if [ "$visibility" != "PRIVATE" ]; then
    warn "Repository $repo is $visibility, not private. It will hold your configuration files."
    confirm "Continue anyway?" || die "aborted"
  fi
}

ensure_local_clone() {
  local repo="$1" dir="$2" origin
  if [ -d "$dir/.git" ]; then
    origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    case "$origin" in
      *"$repo"*|*"$repo.git") ok "using existing checkout $dir" ;;
      *) die "$dir is a git repository for '$origin', not $repo. Choose another directory with --data-dir." ;;
    esac
  else
    if [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
      die "$dir exists and is not empty. Choose another directory with --data-dir."
    fi
    info "Cloning $repo to $dir"
    gh repo clone "$repo" "$dir" -- -q 2>/dev/null
    ok "cloned"
  fi
  if [ ! -f "$dir/macbackup.conf" ]; then
    info "Adding default macbackup.conf"
    cp "$MACBACKUP_ROOT/share/macbackup.conf" "$dir/macbackup.conf"
    cp "$MACBACKUP_ROOT/share/data-readme.md" "$dir/README.md"
    printf '.DS_Store\n' > "$dir/.gitignore"
    if ! git -C "$dir" rev-parse HEAD >/dev/null 2>&1; then
      git -C "$dir" symbolic-ref HEAD refs/heads/main
    fi
    DATA_DIR="$dir"
    ensure_git_identity
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "Initialise macbackup"
    git -C "$dir" push -q -u origin HEAD
    ok "pushed initial configuration"
  fi
}

usage_init() {
  cat <<USAGE
Usage: macbackup init [options]

Logs in to GitHub if needed, creates or clones the private backup repository
and writes the local configuration. Safe to run again.

Options:
  --repo <owner/name>   Backup repository (default: <you>/macbackup-data)
  --data-dir <path>     Local checkout (default: ~/.macbackup-data)
  --no-schedule         Do not install the daily launchd schedule
  --yes, -y             Accept all defaults without asking
USAGE
}
