#!/bin/bash
# macbackup installer. Run with:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/benedictschmieder/macbackup/main/install.sh)"
set -eo pipefail

MACBACKUP_REPO="${MACBACKUP_REPO:-benedictschmieder/macbackup}"
MACBACKUP_HOME="${MACBACKUP_HOME:-$HOME/.macbackup}"

info() { printf '\033[34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "macbackup only runs on macOS."

if ! xcode-select -p >/dev/null 2>&1; then
  info "Installing the Xcode command line tools (a dialog will open; re-run this installer when it finishes)"
  xcode-select --install
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    info "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    if ! grep -qs 'brew shellenv' "$HOME/.zprofile"; then
      printf '\neval "$(%s shellenv)"\n' "$(command -v brew)" >> "$HOME/.zprofile"
    fi
  fi
fi

if ! command -v gh >/dev/null 2>&1; then
  info "Installing the GitHub CLI"
  brew install gh
fi

if [ -d "$MACBACKUP_HOME/.git" ]; then
  info "Updating macbackup in $MACBACKUP_HOME"
  git -C "$MACBACKUP_HOME" pull -q --ff-only
else
  info "Installing macbackup to $MACBACKUP_HOME"
  git clone -q "https://github.com/$MACBACKUP_REPO.git" "$MACBACKUP_HOME"
fi

bin_dir="$(brew --prefix)/bin"
ln -sf "$MACBACKUP_HOME/bin/macbackup" "$bin_dir/macbackup"
chmod +x "$MACBACKUP_HOME/bin/macbackup"

info "Installed: $("$bin_dir/macbackup" version)"
cat <<NEXT

Next steps:
  macbackup init      set up GitHub access and the backup repository
  macbackup backup    on the Mac you want to back up
  macbackup restore   on a new Mac
NEXT
