#!/bin/bash
# Reference information about the Mac; not restored, useful when setting up a new one.

backup_system() {
  info "System information"
  local dest="$DATA_DIR/system"
  fresh_dir "$dest"
  {
    sw_vers
    echo
    echo "Hostname:  $(hostname -s)"
    echo "Model:     $(sysctl -n hw.model 2>/dev/null)"
    echo "Chip:      $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    echo "Memory:    $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GB"
    echo "Homebrew:  $(brew --prefix 2>/dev/null)"
    echo "Shell:     $SHELL"
  } > "$dest/info.txt"
  {
    echo "# Applications present on $(hostname -s). Anything not covered by the Brewfile was installed another way."
    ls /Applications "$HOME/Applications" 2>/dev/null | grep '\.app$' | sort -u
  } > "$dest/applications.txt"
  ok "info.txt, applications.txt"
}

restore_system() {
  if [ -f "$DATA_DIR/system/applications.txt" ]; then
    info "Applications on the old Mac that the Brewfile does not cover are listed in $DATA_DIR/system/applications.txt"
  fi
  return 0
}
