#!/bin/bash
# The restore command: apply the backup to this Mac.

cmd_restore() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --yes|-y) ASSUME_YES=1 ;;
      --only) ONLY_MODULES="$2"; shift ;;
      --only=*) ONLY_MODULES="${1#--only=}" ;;
      -h|--help) usage_restore; return 0 ;;
      *) die "Unknown option for restore: $1 (see 'macbackup restore --help')" ;;
    esac
    shift
  done
  load_config
  ensure_data_repo
  validate_modules "$ONLY_MODULES"
  [ -f "$DATA_DIR/Brewfile" ] || [ -d "$DATA_DIR/dotfiles" ] || die "The backup at $DATA_DIR is empty. Run 'macbackup backup' on the Mac you want to copy first."

  RESTORE_BACKUP_DIR="$HOME/.macbackup-restore-$(date +%Y%m%d-%H%M%S)"
  info "Restoring $DATA_REPO onto $(hostname -s)"
  [ "$DRY_RUN" = 1 ] && log "  dry run: nothing is changed"
  pull_data_repo

  local m
  for m in $MACBACKUP_ALL_MODULES; do
    if module_enabled "$m"; then "restore_$m"; fi
  done

  if [ -d "$RESTORE_BACKUP_DIR" ]; then
    log "Previous versions of replaced files are in $RESTORE_BACKUP_DIR"
  fi
  if [ "$DRY_RUN" != 1 ] && ! schedule_is_loaded; then
    if confirm "Install the daily backup schedule on this Mac now?"; then schedule_install; fi
  fi
  info "Restore finished"
}

usage_restore() {
  cat <<USAGE
Usage: macbackup restore [options]

Applies the backup repository to this Mac: installs the Brewfile, copies
dotfiles and VS Code settings, imports preferences, re-adds LaunchAgents and
login items. Each step asks for confirmation.

Options:
  --only <modules>   Comma separated subset of: $MACBACKUP_ALL_MODULES
  --yes, -y          Do not ask for confirmation
  --dry-run          Show what would be done without changing anything
USAGE
}
