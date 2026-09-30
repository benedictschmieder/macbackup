#!/bin/bash
# launchd agent for the daily backup.

LAUNCHD_LABEL="dev.macbackup.backup"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

AGENT_BIN="$MACBACKUP_ROOT/libexec/macbackup-agent"

cmd_schedule() {
  case "${1:-status}" in
    install) load_config; schedule_install ;;
    access) schedule_access ;;
    remove) schedule_remove ;;
    status) schedule_status ;;
    run) load_config; launchctl kickstart "gui/$(id -u)/$LAUNCHD_LABEL" && ok "backup started in the background; see $MACBACKUP_LOG_DIR/backup.log" ;;
    -h|--help|*) cat <<USAGE
Usage: macbackup schedule <install|remove|status|run>

  install   Register a launchd agent that runs 'macbackup backup' daily
            (time from BACKUP_HOUR/BACKUP_MINUTE in macbackup.conf)
  access    Explain how to give the scheduled run Full Disk Access, which it
            needs to read the preferences of sandboxed apps
  remove    Unregister the agent
  status    Show whether the agent is loaded and the last run
  run       Trigger the agent now, the same way launchd would
USAGE
    ;;
  esac
}

build_agent() {
  # Compiles the launcher once; rebuilding changes its code hash, which would drop a Full Disk Access grant.
  local src="$MACBACKUP_ROOT/share/agent.c" built="$MACBACKUP_ROOT/libexec/agent.c.built"
  if [ -x "$AGENT_BIN" ] && cmp -s "$src" "$built"; then return 0; fi
  command -v cc >/dev/null 2>&1 || return 1
  mkdir -p "$MACBACKUP_ROOT/libexec"
  cc -O2 -o "$AGENT_BIN" "$src" 2>/dev/null || return 1
  codesign --force --sign - --identifier dev.macbackup.agent "$AGENT_BIN" >/dev/null 2>&1 || true
  if [ -f "$built" ]; then
    warn "the launcher was rebuilt; if you had granted it Full Disk Access, grant it again (macbackup schedule access)"
  fi
  cp "$src" "$built"
}

schedule_install() {
  local brew_bin launcher
  brew_bin="$(dirname "$(command -v brew)")"
  mkdir -p "$HOME/Library/LaunchAgents" "$MACBACKUP_LOG_DIR"
  if build_agent; then
    launcher="$AGENT_BIN"
  else
    launcher="/bin/bash"
    warn "could not build the launcher (no C compiler); the schedule runs via /bin/bash and cannot read sandboxed apps' preferences"
  fi
  cat > "$LAUNCHD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$launcher</string>
    <string>$MACBACKUP_ROOT/bin/macbackup</string>
    <string>backup</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$brew_bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>MACBACKUP_SCHEDULED</key>
    <string>1</string>
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
  if [ "$(read_state scheduled)" = 1 ] && [ -n "$(read_state unreadable_domains)" ]; then
    warn "the scheduled run could not read these preference domains:$(read_state unreadable_domains)"
    log "  Give it Full Disk Access: macbackup schedule access"
  fi
  return 0
}

schedule_access() {
  if [ ! -x "$AGENT_BIN" ]; then
    warn "the launcher is not built; run 'macbackup schedule install' first"
    return 0
  fi
  cat <<MSG
Preferences of sandboxed apps (Maccy, Shottr, TextEdit, ...) can only be read by
processes with Full Disk Access. Grant it to the scheduled backup's launcher:

  1. System Settings > Privacy & Security > Full Disk Access
  2. Click "+", press Cmd+Shift+G and paste this path, then click Open:
       $AGENT_BIN
  3. Make sure its switch is on.
  4. Test with: macbackup schedule run && sleep 40 && macbackup schedule status

The launcher is the only thing that gains access; /bin/bash and your other
scripts do not. The path is also in the clipboard now.
MSG
  printf '%s' "$AGENT_BIN" | pbcopy 2>/dev/null || true
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
}
