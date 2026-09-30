#!/bin/bash
# status, doctor and update commands.

cmd_status() {
  load_config
  info "macbackup $MACBACKUP_VERSION"
  log "  repository:  $DATA_REPO"
  log "  checkout:    $DATA_DIR"
  log "  settings:    $DATA_DIR/macbackup.conf"
  log "  modules:     $MODULES"
  if [ -d "$DATA_DIR/.git" ]; then
    local last uncommitted unpushed
    last="$(data_git log -1 --format='%cd (%s)' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || echo none)"
    uncommitted="$(data_git status --porcelain | wc -l | tr -d ' ')"
    unpushed="$(data_git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo '?')"
    log "  last commit: $last"
    log "  pending:     $uncommitted uncommitted files, $unpushed unpushed commits"
  fi
  info "Schedule"
  schedule_status
}

cmd_doctor() {
  local failures=0
  check() { if "$@" >/dev/null 2>&1; then ok "$DOCTOR_LABEL"; else printf '%s  ✗%s %s\n' "$C_RED" "$C_RESET" "$DOCTOR_LABEL"; failures=$((failures + 1)); fi; }
  DOCTOR_LABEL="Homebrew installed";           check command -v brew
  DOCTOR_LABEL="git installed";                check command -v git
  DOCTOR_LABEL="GitHub CLI installed";         check command -v gh
  DOCTOR_LABEL="GitHub CLI logged in";         check gh auth status
  DOCTOR_LABEL="VS Code 'code' command";       check command -v code
  DOCTOR_LABEL="mas (App Store CLI)";          check command -v mas
  DOCTOR_LABEL="local configuration present";  check test -f "$MACBACKUP_CONFIG"
  if [ -f "$MACBACKUP_CONFIG" ]; then
    load_config
    DOCTOR_LABEL="backup checkout is a git repository"; check test -d "$DATA_DIR/.git"
    DOCTOR_LABEL="backup remote reachable";             check data_git ls-remote --exit-code origin HEAD
    DOCTOR_LABEL="daily schedule loaded";               check schedule_is_loaded
    DOCTOR_LABEL="scheduled run can read all preference domains (else: macbackup schedule access)"; check test "$(read_state scheduled)" != 1 -o -z "$(read_state unreadable_domains)"
  fi
  if [ "$failures" -eq 0 ]; then ok "everything looks fine"; else warn "$failures check(s) failed"; fi
  return 0
}

cmd_update() {
  info "Updating macbackup in $MACBACKUP_ROOT"
  git -C "$MACBACKUP_ROOT" pull -q --ff-only || die "update failed; check 'git -C $MACBACKUP_ROOT status'"
  ok "now at $(git -C "$MACBACKUP_ROOT" log -1 --format='%h %s')"
  # The updated code must do the reinstall, not the copy loaded before the pull.
  if [ -f "$MACBACKUP_CONFIG" ] && schedule_is_loaded; then
    exec /bin/bash "$MACBACKUP_ROOT/bin/macbackup" schedule install
  fi
}
