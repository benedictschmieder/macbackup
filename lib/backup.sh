#!/bin/bash
# The backup command: collect, scan, commit, push.

cmd_backup() {
  local push=1 force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-push) push=0 ;;
      --dry-run) DRY_RUN=1 ;;
      --force) force=1 ;;
      --only) ONLY_MODULES="$2"; shift ;;
      --only=*) ONLY_MODULES="${1#--only=}" ;;
      -h|--help) usage_backup; return 0 ;;
      *) die "Unknown option for backup: $1 (see 'macbackup backup --help')" ;;
    esac
    shift
  done
  load_config
  ensure_data_repo
  validate_modules "$ONLY_MODULES"
  mkdir -p "$MACBACKUP_LOG_DIR"
  trim_log "$MACBACKUP_LOG_DIR/backup.log"

  BACKUP_STATUS="failed"
  trap 'backup_exit_handler $?' EXIT
  record_state started "$(timestamp)"
  record_state scheduled "${MACBACKUP_SCHEDULED:-0}"
  info "Backing up $(hostname -s) to $DATA_REPO"

  pull_data_repo
  ensure_backup_owner "$force"
  local previous_entries=0
  [ -f "$DATA_DIR/Brewfile" ] && previous_entries="$(brewfile_entry_count "$DATA_DIR/Brewfile")"

  local m
  for m in $MACBACKUP_ALL_MODULES; do
    if module_enabled "$m"; then "backup_$m"; fi
  done
  write_data_repo_files
  claim_backup

  guard_against_shrinking_brewfile "$previous_entries" "$force"

  info "Scanning for secrets"
  scan_secrets "$DATA_DIR" || { BACKUP_STATUS="secrets"; exit 1; }
  ok "none found"

  if [ "$DRY_RUN" = 1 ]; then
    info "Changes that would be committed (dry run, nothing committed):"
    data_git status --short | sed 's/^/  /'
    [ -n "$(data_git status --porcelain)" ] || log "  none"
    BACKUP_STATUS="dry-run"
    return 0
  fi
  commit_and_push "$push"
  BACKUP_STATUS="ok"
}

backup_exit_handler() {
  local code="$1"
  trap - EXIT
  record_state finished "$(timestamp)"
  record_state result "$BACKUP_STATUS"
  case "$BACKUP_STATUS" in
    ok|dry-run) ;;
    secrets) notify "Backup blocked" "Secrets were found in the collected data. Run 'macbackup backup' to see them." ;;
    *) notify "Backup failed" "See ~/Library/Logs/macbackup/backup.log" ;;
  esac
  exit "$code"
}

trim_log() {
  # Keeps the launchd log from growing without bound.
  local file="$1"
  if [ -f "$file" ] && [ "$(stat -f %z "$file")" -gt 1048576 ]; then
    tail -n 2000 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
}

pull_data_repo() {
  data_git remote get-url origin >/dev/null 2>&1 || return 0
  if ! data_git pull -q --rebase --autostash 2>/dev/null; then
    warn "Could not pull $DATA_REPO (offline or empty remote); continuing with the local copy"
  fi
}

guard_against_shrinking_brewfile() {
  # Refuses to overwrite a full backup with a nearly empty one, e.g. from a freshly set up Mac.
  local previous="$1" force="$2" current
  [ "$previous" -gt 0 ] || return 0
  module_enabled brew || return 0
  current="$(brewfile_entry_count "$DATA_DIR/Brewfile")"
  if [ "$((current * 2))" -lt "$previous" ] && [ "$force" != 1 ]; then
    data_git checkout -q -- Brewfile 2>/dev/null || true
    die "This Mac has $current Homebrew entries but the backup has $previous. Refusing to overwrite it; run 'macbackup restore' on a new Mac first, or use --force if this is intended."
  fi
}

write_data_repo_files() {
  cp "$MACBACKUP_ROOT/share/data-readme.md" "$DATA_DIR/README.md"
  printf '.DS_Store\n' > "$DATA_DIR/.gitignore"
}

ensure_git_identity() {
  if [ -z "$(data_git config user.email)" ]; then
    data_git config user.name "macbackup"
    data_git config user.email "macbackup@$(hostname -s).local"
  fi
}

commit_and_push() {
  local push="$1"
  info "Committing"
  data_git add -A
  if data_git diff --cached --quiet; then
    ok "no changes since the last backup"
  else
    ensure_git_identity
    data_git commit -q -m "backup: $(hostname -s) $(date +%Y-%m-%d)"
    ok "committed: $(data_git show --stat --format= HEAD | tail -1 | sed 's/^ *//')"
  fi
  [ "$push" = 1 ] || return 0
  data_git remote get-url origin >/dev/null 2>&1 || { warn "no remote configured, not pushing"; return 0; }
  if data_git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    if [ "$(data_git rev-list --count '@{upstream}..HEAD')" -gt 0 ]; then
      data_git push -q && ok "pushed to $DATA_REPO"
    fi
  else
    data_git push -q -u origin HEAD && ok "pushed to $DATA_REPO"
  fi
}

usage_backup() {
  cat <<USAGE
Usage: macbackup backup [options]

Collects software and configuration into the backup repository, scans it for
secrets, commits and pushes. Nothing is pushed when nothing changed.

Options:
  --only <modules>   Comma separated subset of: $MACBACKUP_ALL_MODULES
  --no-push          Commit locally but do not push
  --dry-run          Collect and show the changes, but do not commit
  --force            Allow a Brewfile that is much smaller than the previous one
USAGE
}
