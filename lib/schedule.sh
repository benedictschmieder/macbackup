#!/bin/bash
# launchd agent for the daily backup.

LAUNCHD_LABEL="dev.macbackup.backup"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

cmd_schedule() {
  case "${1:-status}" in
    install) load_config; schedule_install ;;
    remove) schedule_remove ;;
    status) schedule_status ;;
    run) load_config; launchctl kickstart "gui/$(id -u)/$LAUNCHD_LABEL" && ok "backup started in the background; see $MACBACKUP_LOG_DIR/backup.log" ;;
    -h|--help|*) cat <<USAGE
Usage: macbackup schedule <install|remove|status|run>

  install   Register a launchd agent that runs 'macbackup backup' daily
            (time from BACKUP_HOUR/BACKUP_MINUTE in macbackup.conf)
  remove    Unregister the agent
  status    Show whether the agent is loaded and the last run
  run       Trigger the agent now, the same way launchd would
USAGE
    ;;
  esac
}

schedule_install() {
  local brew_bin
  brew_bin="$(dirname "$(command -v brew)")"
  mkdir -p "$HOME/Library/LaunchAgents" "$MACBACKUP_LOG_DIR"
  cat > "$LAUNCHD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$MACBACKUP_ROOT/bin/macbackup</string>
    <string>backup</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$brew_bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>${BACKUP_HOUR:-12}</integer>
    <key>Minute</key>
    <integer>${BACKUP_MINUTE:-0}</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$MACBACKUP_LOG_DIR/backup.log</string>
  <key>StandardErrorPath</key>
  <string>$MACBACKUP_LOG_DIR/backup.log</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_PLIST"
  ok "daily backup scheduled at $(printf '%02d:%02d' "${BACKUP_HOUR:-12}" "${BACKUP_MINUTE:-0}") (missed runs happen after wake-up)"
}

schedule_remove() {
  launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  rm -f "$LAUNCHD_PLIST"
  ok "schedule removed"
}

schedule_is_loaded() {
  launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1
}

schedule_status() {
  if schedule_is_loaded; then
    ok "launchd agent $LAUNCHD_LABEL is loaded"
    launchctl print "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null | grep -E 'last exit code|runs =' | sed 's/^[[:space:]]*/  /'
    [ -f "$LAUNCHD_PLIST" ] && log "  scheduled daily at $(printf '%02d:%02d' "$(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:Hour' "$LAUNCHD_PLIST")" "$(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:Minute' "$LAUNCHD_PLIST")")"
  else
    log "  no schedule installed (run 'macbackup schedule install')"
  fi
  local started result
  started="$(read_state started)"; result="$(read_state result)"
  [ -n "$started" ] && log "  last run: $started, result: ${result:-unknown}"
  return 0
}
