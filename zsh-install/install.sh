#!/bin/sh
#
# zsh-install — portable zsh + Oh My Zsh + Powerlevel10k setup
# https://github.com/bhataprameya/dev-setup
#
# One-liner:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install/install.sh)"
#
# Works on macOS and Linux (glibc/musl), as root or a normal user, under any
# POSIX shell (sh/dash/ash/bash/zsh).
# Idempotent: safe to re-run. Existing configs are backed up, then cleanly replaced/updated.
#
# zsh handling: the installer health-checks zsh (its core modules must load) and
# prefers the system zsh over a broken user-local shadow build (e.g. a source
# build in ~/.local/bin). If no working zsh exists it installs the distro one,
# which also provides the missing core module .so files.
#
# Optional env overrides (mostly for testing/mirrors):
#   NO_CHSH=1        don't change the login shell
#   NO_FONT=1        don't install the MesloLGS NF font
#   NO_ZSH_INSTALL=1 don't try to install zsh via a package manager
#   NO_EXEC=1        don't auto-launch zsh at the end
#   NO_BASH_HANDOFF=1 don't add the bash -> zsh handoff fallback
#   ALL_USERS=1      also set up every real user + root (needs root/sudo)
#   ASSET_BASE=...   where to fetch .p10k.zsh from (http(s) URL or local dir)
#   ZSH_CANDIDATES=... space-separated system zsh paths to try before PATH lookup
#   TEST_RECORDED_SHELL=... fake the user's recorded login shell (tests)
#   *_REPO=...       override any source git repo (local path or URL)

set -eu

# --------------------------------------------------------------------------- #
# Configuration (all overridable via env)
# --------------------------------------------------------------------------- #
: "${OMZ_REPO:=https://github.com/ohmyzsh/ohmyzsh.git}"
: "${P10K_REPO:=https://github.com/romkatv/powerlevel10k.git}"
: "${AUTOSUGGEST_REPO:=https://github.com/zsh-users/zsh-autosuggestions.git}"
: "${SYNTAX_REPO:=https://github.com/zsh-users/zsh-syntax-highlighting.git}"
: "${COMPLETIONS_REPO:=https://github.com/zsh-users/zsh-completions.git}"
: "${FONT_BASE:=https://github.com/romkatv/powerlevel10k-media/raw/master}"
: "${ASSET_BASE:=https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install}"
: "${NO_CHSH:=0}"
: "${NO_FONT:=0}"
: "${NO_ZSH_INSTALL:=0}"
# Space-separated system zsh paths, tried before PATH lookup. Override for
# distros that install elsewhere (NixOS, custom prefixes, ...).
: "${ZSH_CANDIDATES:=/usr/bin/zsh /bin/zsh /usr/local/bin/zsh /opt/homebrew/bin/zsh /opt/local/bin/zsh}"

ZSH_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM_DIR="$ZSH_DIR/custom"
TS="$(date +%Y%m%d-%H%M%S)"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
c_blue='\033[1;34m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'; c_red='\033[1;31m'; c_off='\033[0m'
log()  { printf "${c_blue}==>${c_off} %s\n" "$*"; }
ok()   { printf "${c_green}  ok${c_off} %s\n" "$*"; }
warn() { printf "${c_yellow}  ! ${c_off} %s\n" "$*"; }
die()  { printf "${c_red}error:${c_off} %s\n" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"

# Backup a path if it exists (file or dir) and isn't a symlink we manage.
backup() {
  _p="$1"
  if [ -e "$_p" ] || [ -L "$_p" ]; then
    mv "$_p" "$_p.pre-zsh-install.$TS"
    warn "backed up existing $(basename "$_p") -> $(basename "$_p").pre-zsh-install.$TS"
  fi
}

# Clone a repo, or update it in place if it's already a git checkout (idempotent).
clone_or_update() {
  _repo="$1"; _dest="$2"
  if [ -d "$_dest/.git" ]; then
    git -C "$_dest" remote set-url origin "$_repo" 2>/dev/null || true
    if git -C "$_dest" pull --ff-only --quiet 2>/dev/null; then
      ok "updated $(basename "$_dest")"
    else
      warn "could not fast-forward $(basename "$_dest"); re-cloning"
      rm -rf "$_dest"; git clone --depth=1 --quiet "$_repo" "$_dest"; ok "installed $(basename "$_dest")"
    fi
  else
    rm -rf "$_dest"
    git clone --depth=1 --quiet "$_repo" "$_dest"
    ok "installed $(basename "$_dest")"
  fi
}

# Fetch an asset (e.g. .p10k.zsh) into a destination path.
# ASSET_BASE may be an http(s) URL, a local directory, or a file:// URL.
get_asset() {
  _name="$1"; _dest="$2"
  # Prefer a copy sitting next to this script (repo clone / local run).
  if [ -n "${SCRIPT_DIR:-}" ] && [ -f "$SCRIPT_DIR/$_name" ]; then
    cp "$SCRIPT_DIR/$_name" "$_dest"; return 0
  fi
  case "$ASSET_BASE" in
    http*://*)
      if have curl; then curl -fsSL "$ASSET_BASE/$_name" -o "$_dest"
      elif have wget; then wget -qO "$_dest" "$ASSET_BASE/$_name"
      else die "need curl or wget to download $_name"; fi ;;
    file://*) cp "${ASSET_BASE#file://}/$_name" "$_dest" ;;
    *)        cp "$ASSET_BASE/$_name" "$_dest" ;;
  esac
}

# Best-effort resolve of this script's directory (empty when piped from curl).
SCRIPT_DIR=""
case "${0:-}" in
  -*|sh|bash|dash|zsh|ash) : ;;                 # piped: $0 is the shell name
  *) if [ -f "$0" ]; then
       SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
     fi ;;
esac

# --------------------------------------------------------------------------- #
# 1. Ensure git + zsh are present
# --------------------------------------------------------------------------- #
install_pkg() {
  # $@ = package names to install with whatever package manager exists
  sudo=""
  if [ "$(id -u)" -ne 0 ] && have sudo; then sudo="sudo"; fi
  if   have apt-get; then $sudo apt-get update -qq && $sudo apt-get install -y "$@"
  elif have dnf;     then $sudo dnf install -y "$@"
  elif have yum;     then $sudo yum install -y "$@"
  elif have pacman;  then $sudo pacman -Sy --noconfirm "$@"
  elif have zypper;  then $sudo zypper install -y "$@"
  elif have apk;     then $sudo apk add "$@"
  elif have brew;    then brew install "$@"
  else return 1; fi
}

log "Detected OS: $OS"

have git || { log "Installing git"; install_pkg git || die "git is required but not installed"; }

# A zsh binary can exist but be useless: if it was built for a module path that
# doesn't exist on this machine, core modules (zsh/zle, zsh/parameter, ...) fail
# with "cannot open shared object file: zsh/zle.so". Verify before trusting any
# zsh, and prefer the system one over a possibly-broken user-local shadow build
# (common source-build location: ~/.local/bin/zsh on top of PATH).
zsh_usable() {
  _z="$1"
  "$_z" -f -c '
    for d in ${HOME}/.local/lib/*/zsh/*(N) ${HOME}/.local/lib/zsh/*(N); do
      [ -d "$d/zsh" ] && module_path=("$d" $module_path)
    done
    zmodload zsh/zle 2>/dev/null || exit 1
    zmodload zsh/parameter 2>/dev/null || exit 1
    zmodload zsh/datetime 2>/dev/null || exit 1
    zmodload zsh/stat 2>/dev/null || exit 1
    exit 0
  ' >/dev/null 2>&1
}

find_working_zsh() {
  # shellcheck disable=SC2086 # intentional word-splitting of ZSH_CANDIDATES
  for c in $ZSH_CANDIDATES; do
    [ -x "$c" ] || continue
    if zsh_usable "$c"; then ZSH_BIN="$c"; return 0; fi
  done
  _p="$(command -v zsh 2>/dev/null || true)"
  if [ -n "$_p" ] && [ -x "$_p" ] && zsh_usable "$_p"; then
    ZSH_BIN="$_p"; return 0
  fi
  return 1
}

if find_working_zsh; then
  ok "zsh: $ZSH_BIN (core modules load)"
else
  warn "zsh is missing or broken: core modules (zsh/zle, zsh/parameter, ...) do not load."
  warn "This is usually a source-built zsh in ~/.local/bin shadowing the system one."
  if [ "$NO_ZSH_INSTALL" = "1" ]; then
    die "no working zsh found (NO_ZSH_INSTALL=1 set). Install one, e.g.: sudo apt-get install -y zsh"
  fi
  log "Installing system zsh (this also installs the missing core module .so files)"
  if [ "$OS" = "Darwin" ]; then
    have brew && brew install zsh || die "zsh missing and Homebrew not found; install zsh manually"
  else
    install_pkg zsh || die "could not install zsh; install it manually and re-run"
  fi
  find_working_zsh || die "zsh still not functional after install. Fix manually, e.g.: sudo apt-get install -y zsh"
  ok "zsh: $ZSH_BIN (core modules load)"
fi

# --------------------------------------------------------------------------- #
# 2. Oh My Zsh + theme + plugins
# --------------------------------------------------------------------------- #
log "Installing Oh My Zsh"
clone_or_update "$OMZ_REPO" "$ZSH_DIR"

log "Installing Powerlevel10k theme"
mkdir -p "$ZSH_CUSTOM_DIR/themes" "$ZSH_CUSTOM_DIR/plugins"
clone_or_update "$P10K_REPO" "$ZSH_CUSTOM_DIR/themes/powerlevel10k"

log "Installing plugins"
clone_or_update "$AUTOSUGGEST_REPO"   "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
clone_or_update "$SYNTAX_REPO"        "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
clone_or_update "$COMPLETIONS_REPO"   "$ZSH_CUSTOM_DIR/plugins/zsh-completions"

# --------------------------------------------------------------------------- #
# 3. MesloLGS NF font (Powerlevel10k's recommended font)
# --------------------------------------------------------------------------- #
if [ "$NO_FONT" = "1" ]; then
  warn "skipping font install (NO_FONT=1)"
else
  log "Installing MesloLGS NF font"
  if [ "$OS" = "Darwin" ]; then FONT_DIR="$HOME/Library/Fonts"; else FONT_DIR="$HOME/.local/share/fonts"; fi
  mkdir -p "$FONT_DIR"
  font_ok=1
  set -- "Regular" "Bold" "Italic" "Bold Italic"
  for f in "$@"; do
    enc="MesloLGS%20NF%20$(printf '%s' "$f" | sed 's/ /%20/g').ttf"
    out="$FONT_DIR/MesloLGS NF $f.ttf"
    if [ -s "$out" ]; then continue; fi
    if have curl && curl -fsSL "$FONT_BASE/$enc" -o "$out" 2>/dev/null && [ -s "$out" ]; then :;
    elif have wget && wget -qO "$out" "$FONT_BASE/$enc" 2>/dev/null && [ -s "$out" ]; then :;
    else rm -f "$out"; font_ok=0; fi
  done
  if [ "$font_ok" = "1" ]; then
    ok "MesloLGS NF installed to $FONT_DIR"
    [ "$OS" != "Darwin" ] && have fc-cache && fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
  else
    warn "font download failed (non-fatal); set your terminal font to 'MesloLGS NF' manually"
  fi
fi

# --------------------------------------------------------------------------- #
# 4. Powerlevel10k prompt config (.p10k.zsh)
# --------------------------------------------------------------------------- #
log "Installing prompt config (~/.p10k.zsh)"
backup "$HOME/.p10k.zsh"
get_asset ".p10k.zsh" "$HOME/.p10k.zsh" || die "failed to install .p10k.zsh"
ok ".p10k.zsh installed"

# --------------------------------------------------------------------------- #
# 5. Activate Oh My Zsh + Powerlevel10k in ~/.zshrc (non-destructive)
#    NEVER overwrites an existing .zshrc — your custom config is preserved.
#      - no ~/.zshrc      -> write a starter template
#      - ~/.zshrc exists  -> append a marker-guarded activation block
#                            (idempotent; skipped on re-runs once present)
# --------------------------------------------------------------------------- #
# Build the starter template and the activation block into temp files so the
# same logic serves both the current user and ALL_USERS provisioning.
_zshrc_full="$(mktemp)"
_zshrc_block="$(mktemp)"
trap 'rm -f "$_zshrc_full" "$_zshrc_block"' EXIT

cat > "$_zshrc_full" <<'ZSHRC'
# ~/.zshrc — generated by dev-setup (github.com/bhataprameya/dev-setup)
# Clean, portable Oh My Zsh + Powerlevel10k setup. Add your own tweaks below.

# Enable Powerlevel10k instant prompt (keep near the top).
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Source-built zsh keeps core modules in per-version dirs; add every user-local
# module dir we can find so a hand-compiled zsh under ~/.local works alongside
# the distro one. No-op on normal installs.
for _moddir in ${HOME}/.local/lib/*/zsh/*(N) ${HOME}/.local/lib/zsh/*(N); do
  [ -d "$_moddir/zsh" ] && module_path=("$_moddir" $module_path)
done
unset _moddir

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# zsh-completions must be on fpath before oh-my-zsh is sourced
fpath+="${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src"

CASE_SENSITIVE="false"
HYPHEN_INSENSITIVE="true"
DISABLE_AUTO_TITLE="true"
COMPLETION_WAITING_DOTS="true"
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 13

# zsh-syntax-highlighting must be last in this list.
plugins=(
  git
  z
  sudo
  colored-man-pages
  command-not-found
  copypath
  dirhistory
  extract
  zsh-completions
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

# ---- User configuration -------------------------------------------------------
export LANG="${LANG:-en_US.UTF-8}"
export EDITOR="${EDITOR:-vim}"

# History
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY APPEND_HISTORY INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS HIST_VERIFY

# Navigation / completion behavior
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS GLOB_DOTS

# Portable colored ls (GNU coreutils vs BSD/macOS)
if ls --color=auto >/dev/null 2>&1; then
  alias ls='ls --color=auto'
else
  alias ls='ls -G'
fi
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'

# Lazy-load nvm if present, so shell startup stays fast.
if [ -d "$HOME/.nvm" ]; then
  export NVM_DIR="$HOME/.nvm"
  _load_nvm() {
    unset -f nvm node npm npx 2>/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
  }
  for _c in nvm node npm npx; do
    eval "${_c}() { _load_nvm; ${_c} \"\$@\"; }"
  done
  unset _c
fi

# Powerlevel10k prompt configuration.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
ZSHRC

cat > "$_zshrc_block" <<'ZSHRC_BLOCK'

# >>> zsh-install: oh-my-zsh + powerlevel10k >>>
# Added by dev-setup (github.com/bhataprameya/dev-setup). Safe to delete.
# Activates the Oh My Zsh + Powerlevel10k setup installed by this script.
# Skipped if Oh My Zsh is already loaded (e.g. your .zshrc already sources it).
if [[ -z "${ZSH:-}" ]]; then
  if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
  fi
  export ZSH="$HOME/.oh-my-zsh"
  ZSH_THEME="powerlevel10k/powerlevel10k"
  fpath+="${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src"
  plugins=(git z sudo colored-man-pages command-not-found copypath dirhistory extract zsh-completions zsh-autosuggestions zsh-syntax-highlighting)
  source "$ZSH/oh-my-zsh.sh"
  [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
fi
# <<< zsh-install: oh-my-zsh + powerlevel10k <<<
ZSHRC_BLOCK

_ZSHRC_MARKER="# >>> zsh-install: oh-my-zsh + powerlevel10k >>>"

# install_zshrc <home> [sudo_prefix] — non-destructively activate the setup.
install_zshrc() {
  _home="$1"; _sudo="${2:-}"
  _rc="$_home/.zshrc"
  if [ ! -e "$_rc" ]; then
    log "No .zshrc in $_home; writing starter template"
    $_sudo cp "$_zshrc_full" "$_rc" || return 1
    ok "starter .zshrc written ($_home)"
  elif $_sudo grep -qF "$_ZSHRC_MARKER" "$_rc" 2>/dev/null; then
    ok ".zshrc already activated ($_home); left untouched"
  else
    log "Existing .zshrc found in $_home; appending activation block (your config is preserved)"
    $_sudo tee -a "$_rc" < "$_zshrc_block" >/dev/null || return 1
    ok "activation block appended to .zshrc ($_home)"
    warn "p10k instant prompt works best at the TOP of .zshrc; move the block up for instant prompt"
  fi
}

install_zshrc "$HOME" "" || die "failed to write ~/.zshrc"

# --------------------------------------------------------------------------- #
# 6. Make zsh the default login shell
# --------------------------------------------------------------------------- #

# What shell does the system actually have on record for this user?
recorded_shell() {
  # TEST_RECORDED_SHELL lets the test suite simulate any login-shell state
  # deterministically, independent of the host account.
  if [ -n "${TEST_RECORDED_SHELL:-}" ]; then printf '%s\n' "$TEST_RECORDED_SHELL"; return 0; fi
  if have getent; then getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7
  elif [ "$OS" = "Darwin" ] && have dscl; then
    dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}'
  fi
}

# chsh only accepts shells listed in /etc/shells. Make sure ours is there.
register_shell() {
  _sh="$1"
  if grep -qxF "$_sh" /etc/shells 2>/dev/null; then return 0; fi
  if [ "$(id -u)" -eq 0 ] || [ -w /etc/shells ]; then
    # /etc/shells may not exist at all on minimal images
    echo "$_sh" >> /etc/shells 2>/dev/null || true
  elif have sudo; then
    echo "$_sh" | sudo tee -a /etc/shells >/dev/null 2>&1 || true
  fi
  grep -qxF "$_sh" /etc/shells 2>/dev/null
}

# Fallback for machines where chsh is unavailable or gets reverted (managed
# boxes, remote devspaces): hand off from an interactive bash login to zsh.
# Guarded so it never loops and never affects non-interactive shells/scripts.
install_bash_handoff() {
  _marker="# >>> zsh-install: launch zsh >>>"
  _block="$_marker
# Start zsh for interactive bash sessions (default shell could not be changed).
if [ -z \"\${ZSH_VERSION:-}\" ] && [ -z \"\${ZSH_INSTALL_NO_HANDOFF:-}\" ] && [ -t 1 ] && case \$- in *i*) true;; *) false;; esac; then
  export SHELL=\"$ZSH_BIN\"
  exec \"$ZSH_BIN\" -l
fi
# <<< zsh-install: launch zsh <<<"
  _added=0
  for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -e "$f" ] || { [ "$f" = "$HOME/.bashrc" ] || continue; : > "$f"; }
    if grep -qF "$_marker" "$f" 2>/dev/null; then _added=1; continue; fi
    if printf '\n%s\n' "$_block" >> "$f"; then _added=1; fi
  done
  [ "$_added" = "1" ]
}

CURRENT_RECORDED="$(recorded_shell || true)"

if [ "$NO_CHSH" = "1" ]; then
  warn "skipping default-shell change (NO_CHSH=1)"
elif [ -n "$CURRENT_RECORDED" ] && [ "$CURRENT_RECORDED" = "$ZSH_BIN" ]; then
  ok "zsh is already your default shell"
else
  log "Setting zsh as your default shell"

  # Pick a target chsh will actually accept: prefer the zsh we found, but fall
  # back to any zsh already listed in /etc/shells (e.g. /bin/zsh) if we cannot
  # register ours (no sudo / read-only /etc/shells).
  CHSH_TARGET="$ZSH_BIN"
  if ! register_shell "$ZSH_BIN"; then
    ALT="$(grep -E '/zsh$' /etc/shells 2>/dev/null | head -1 || true)"
    if [ -n "$ALT" ] && [ -x "$ALT" ]; then
      CHSH_TARGET="$ALT"
      warn "$ZSH_BIN is not in /etc/shells; using $ALT instead"
    else
      warn "could not register a zsh in /etc/shells"
    fi
  fi

  changed=0
  if have chsh; then
    # chsh reads the password from the controlling terminal, so feed it /dev/tty
    # when available (works even when the script itself was piped from curl).
    if { [ -e /dev/tty ] && chsh -s "$CHSH_TARGET" </dev/tty; } || chsh -s "$CHSH_TARGET"; then
      changed=1
    fi
  fi

  # Verify it actually stuck — chsh can "succeed" yet be reverted on managed hosts.
  NEW_RECORDED="$(recorded_shell || true)"
  case "$NEW_RECORDED" in
    *zsh) changed=1 ;;
    "")   : ;;                # cannot verify; trust chsh's exit status
    *)    [ "$changed" = "1" ] && changed=0 ;;
  esac

  if [ "$changed" = "1" ]; then
    ok "default shell set to zsh (applies to new logins)"
  else
    warn "could not change the login shell"
    if [ "${NO_BASH_HANDOFF:-0}" != "1" ] && install_bash_handoff; then
      ok "added a bash -> zsh handoff so new terminals still start zsh"
    else
      warn "run this yourself:  chsh -s $CHSH_TARGET"
    fi
  fi
fi

# --------------------------------------------------------------------------- #
# 7. Optional: provision every real user (and root) with the same setup
#    Enabled with ALL_USERS=1. Needs root (directly or via sudo).
#    Service/system accounts (nologin, false, ...) are always skipped.
# --------------------------------------------------------------------------- #
if [ "${ALL_USERS:-0}" = "1" ]; then
  log "Provisioning all users (ALL_USERS=1)"

  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    if have sudo; then SUDO="sudo"; else warn "ALL_USERS=1 needs root or sudo; skipping"; fi
  fi

  if [ "$(id -u)" -eq 0 ] || [ -n "$SUDO" ]; then
    # user:home pairs for root + real login accounts, excluding service accounts
    list_users() {
      if have getent; then
        getent passwd | awk -F: '
          ($3 == 0 || $3 >= 1000) &&
          $7 !~ /(nologin|\/false|\/sync|\/halt|\/shutdown)/ &&
          $6 != "" && $6 != "/" && $6 !~ /nonexistent/ { print $1 ":" $6 }'
      elif [ "$OS" = "Darwin" ] && have dscl; then
        dscl . -list /Users UniqueID 2>/dev/null | awk '$2 == 0 || $2 >= 500 {print $1}' | while read -r u; do
          case "$u" in _*|daemon|nobody) continue ;; esac
          h="$(dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
          [ -n "$h" ] && [ -d "$h" ] && printf '%s:%s\n' "$u" "$h"
        done
      fi
    }

    provision_user() { # $1=user  $2=home
      _u="$1"; _uh="$2"
      [ -d "$_uh" ] || return 0
      # oh-my-zsh + theme + plugins: copy the tree we already built
      if [ ! -d "$_uh/.oh-my-zsh" ]; then
        $SUDO cp -R "$ZSH_DIR" "$_uh/.oh-my-zsh" 2>/dev/null || return 1
      fi
      # back up their .p10k.zsh before replacing it; .zshrc is never replaced
      # (it is appended to / templated non-destructively by install_zshrc).
      for f in .p10k.zsh; do
        if [ -e "$_uh/$f" ] && ! [ -e "$_uh/$f.pre-zsh-install.$TS" ]; then
          $SUDO cp -p "$_uh/$f" "$_uh/$f.pre-zsh-install.$TS" 2>/dev/null || true
        fi
      done
      install_zshrc "$_uh" "$SUDO" || return 1
      $SUDO cp "$HOME/.p10k.zsh" "$_uh/.p10k.zsh" 2>/dev/null || return 1
      $SUDO chown -R "$_u" "$_uh/.oh-my-zsh" "$_uh/.zshrc" "$_uh/.p10k.zsh" 2>/dev/null || true
      # point their login shell at zsh
      if have chsh; then
        $SUDO chsh -s "${CHSH_TARGET:-$ZSH_BIN}" "$_u" >/dev/null 2>&1 && return 0
      fi
      if have usermod; then
        $SUDO usermod -s "${CHSH_TARGET:-$ZSH_BIN}" "$_u" >/dev/null 2>&1 && return 0
      fi
      if [ "$OS" = "Darwin" ] && have dscl; then
        $SUDO dscl . -change "/Users/$_u" UserShell "$(dscl . -read "/Users/$_u" UserShell 2>/dev/null | awk '{print $2}')" "${CHSH_TARGET:-$ZSH_BIN}" >/dev/null 2>&1 && return 0
      fi
      return 1
    }

    ME="$(id -un)"
    list_users | while IFS=: read -r u uh; do
      [ -n "$u" ] || continue
      [ "$u" = "$ME" ] && continue            # already done above
      if provision_user "$u" "$uh"; then
        ok "provisioned $u ($uh)"
      else
        warn "could not fully provision $u"
      fi
    done
  fi
fi

# Clean up temp files now (the final `exec` below bypasses the EXIT trap).
rm -f "$_zshrc_full" "$_zshrc_block" 2>/dev/null || true

# --------------------------------------------------------------------------- #
# Done — launch zsh right away so the new setup is live immediately
# --------------------------------------------------------------------------- #
printf "\n${c_green}✔ zsh-install complete.${c_off}\n"
printf "  Set your terminal font to \"MesloLGS NF\" so the prompt icons render.\n"

# The one thing a script can't do is pick your terminal app's font — that lives
# in the terminal emulator's own settings, not in any shell config.
if [ "${NO_EXEC:-0}" != "1" ] && [ -t 1 ]; then
  printf "  Launching zsh now...\n\n"
  exec "$ZSH_BIN" -l
else
  printf "  Start a new terminal, or run:  exec zsh\n\n"
fi

