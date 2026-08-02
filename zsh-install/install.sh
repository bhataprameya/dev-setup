#!/usr/bin/env bash
#
# ============================================================================
#  install.sh — portable zsh + Oh My Zsh + Powerlevel10k setup
# ============================================================================
#
#  Goal: give ANY machine the SAME zsh experience with byte-identical config.
#
#  Supported environments (auto-detected):
#    * Linux:  Debian/Ubuntu (apt), Fedora/RHEL (dnf/yum), Arch (pacman),
#              Alpine (apk), openSUSE (zypper), Gentoo (emerge)
#    * macOS:  Homebrew (brew)
#    * FreeBSD (pkg)
#    * Root or non-root (uses sudo when available), WSL, containers.
#
#  What it does:
#    1. Verifies zsh actually WORKS — its loadable modules (zle.so, stat.so,
#       ...) must load, not just that the binary exists. This catches the
#       classic "cannot open shared object file: zsh/zle.so" failure on a
#       half-installed / source-built zsh.
#    2. Installs zsh via the right package manager ONLY if missing or broken.
#    3. Installs Oh My Zsh, powerlevel10k, and plugins (idempotent).
#    4. Installs ONE canonical ~/.zshrc (embedded below) — identical on every
#       machine — after backing up any existing config.
#    5. Optionally sets zsh as the default shell.
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install/install.sh | bash
#    bash install.sh [-y|--yes] [--no-shell] [--rc /path/to/zshrc] [-h]
#
#  Flags:
#    -y, --yes        skip prompts (auto-install dependencies)
#    --no-shell       do not change the default shell
#    --rc <file>      install this .zshrc instead of the canonical embedded one
#    -h, --help       show this help
#
# ============================================================================

set -euo pipefail

# ---- configuration ---------------------------------------------------------
ASSUME_YES=0
CHANGE_SHELL=1
# When run via `curl | bash` there is no script file (BASH_SOURCE is empty),
# so SCRIPT_DIR stays unset and sibling-file overrides (a zshrc or p10k.zsh
# next to the script) are disabled — the canonical embedded config is used.
# `${BASH_SOURCE[0]:-}` is a safe read under set -u even if the array is empty.
_src="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [ -n "$_src" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$_src")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
fi
unset _src
CUSTOM_RC_FILE="${DEV_SETUP_ZSH_RC:-}"
ZSH_BIN=""
# Scratch rc file used on the embedded-config path; cleaned up on exit.
tmprc=""
trap 'rm -f "${tmprc:-}"' EXIT

OMZ_URL="https://github.com/ohmyzsh/ohmyzsh.git"
P10K_URL="https://github.com/romkatv/powerlevel10k.git"
AUTOSUGGEST_URL="https://github.com/zsh-users/zsh-autosuggestions.git"
SYNTAX_HL_URL="https://github.com/zsh-users/zsh-syntax-highlighting.git"
COMPLETIONS_URL="https://github.com/zsh-users/zsh-completions.git"

# ---- helpers ---------------------------------------------------------------
log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m   %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m  %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

usage() {
  local src="${BASH_SOURCE[0]:-}"
  _usage_fallback() {
    cat <<'USAGE_EOF'
install.sh — portable zsh + Oh My Zsh + Powerlevel10k setup.
  Usage: bash install.sh [-y|--yes] [--no-shell] [--rc /path/to/zshrc] [-h]
  -y, --yes     skip prompts (auto-install dependencies)
  --no-shell    do not change the default shell
  --rc <file>   install this .zshrc instead of the canonical embedded one
  -h, --help    show this help
USAGE_EOF
  }
  [ -n "$src" ] && [ -r "$src" ] || { _usage_fallback; return 0; }
  sed -n '2,53p' "$src" | sed 's/^# \{0,1\}//' | sed '/^===/d'
}

# ---- platform / package manager detection ----------------------------------
detect_platform() {
  platform="$(uname -s | tr '[:upper:]' '[:lower:]')"
  distro=""

  if [ "$(id -u 2>/dev/null || printf 0)" = "0" ]; then
    ROOT=1
  else
    ROOT=0
  fi

  SUDO=""
  if [ "$ROOT" -ne 1 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi

  pkg_mgr=""
  case "$platform" in
    darwin)
      command -v brew >/dev/null 2>&1 && pkg_mgr="brew"
      ;;
    freebsd)
      command -v pkg >/dev/null 2>&1 && pkg_mgr="pkg"
      ;;
    mingw*|msys*|cygwin*)
      # Git Bash / MSYS2 — zsh is not a first-class shell here.
      die "Windows Git Bash is not supported for zsh. Use WSL instead."
      ;;
    linux)
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        distro="${ID:-linux}"
      fi
      case "$distro" in
        debian|ubuntu|linuxmint|kali|pop|elementary|raspbian|pureos)
          command -v apt-get >/dev/null 2>&1 && pkg_mgr="apt" ;;
        fedora|rhel|centos|rocky|almalinux)
          if command -v dnf >/dev/null 2>&1; then pkg_mgr="dnf"; else pkg_mgr="yum"; fi ;;
        arch|manjaro|endeavouros|artix)
          command -v pacman >/dev/null 2>&1 && pkg_mgr="pacman" ;;
        alpine)
          command -v apk >/dev/null 2>&1 && pkg_mgr="apk" ;;
        opensuse*|suse|sles)
          command -v zypper >/dev/null 2>&1 && pkg_mgr="zypper" ;;
        gentoo)
          command -v emerge >/dev/null 2>&1 && pkg_mgr="emerge" ;;
      esac
      # Fallback: probe by presence of known package managers.
      if [ -z "$pkg_mgr" ]; then
        for m in apt-get dnf yum pacman apk zypper emerge; do
          if command -v "$m" >/dev/null 2>&1; then pkg_mgr="$m"; break; fi
        done
      fi
      ;;
    *) pkg_mgr="" ;;
  esac
}

pkg_install() {
  # Install the given package names via the detected package manager.
  local -a names=("$@")
  case "$pkg_mgr" in
    apt)
      $SUDO apt-get update -qq >/dev/null 2>&1 || warn "apt-get update failed; trying install anyway"
      if ! $SUDO apt-get install -y "${names[@]}"; then
        die "package install failed. Run manually: $SUDO apt-get install -y ${names[*]}"
      fi
      ;;
    dnf)
      $SUDO dnf install -y "${names[@]}" || die "package install failed. Run manually: $SUDO dnf install -y ${names[*]}"
      ;;
    yum)
      $SUDO yum install -y "${names[@]}" || die "package install failed. Run manually: $SUDO yum install -y ${names[*]}"
      ;;
    pacman)
      $SUDO pacman -Sy --noconfirm "${names[@]}" || die "package install failed. Run manually: $SUDO pacman -S ${names[*]}"
      ;;
    apk)
      $SUDO apk add --no-cache "${names[@]}" || die "package install failed. Run manually: $SUDO apk add ${names[*]}"
      ;;
    zypper)
      $SUDO zypper -n install "${names[@]}" || die "package install failed. Run manually: $SUDO zypper install ${names[*]}"
      ;;
    emerge)
      $SUDO emerge -q "${names[@]}" || die "package install failed. Run manually: $SUDO emerge ${names[*]}"
      ;;
    brew)
      brew install "${names[@]}" || die "package install failed. Run manually: brew install ${names[*]}"
      ;;
    pkg)
      $SUDO pkg install -y "${names[@]}" || die "package install failed. Run manually: $SUDO pkg install ${names[*]}"
      ;;
    *)
      die "no supported package manager detected. Install manually: ${names[*]}"
      ;;
  esac
}

# ---- zsh presence + health check --------------------------------------------
# A zsh binary can exist but be useless: if it was built with a compile-time
# module path that doesn't exist on this machine, core modules (zle, stat,
# datetime, parameter) fail to load with "cannot open shared object file".
# We test with `-f` (no config files) and also add any user-local module dirs
# under ~/.local, so a source-built zsh is treated as healthy.
zsh_module_ok() {
  local zsh="$1"
  "$zsh" -f -c '
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
  # Prefer system zsh over a broken user-local shadow binary.
  local -a candidates=()
  for c in /usr/bin/zsh /usr/local/bin/zsh /bin/zsh /opt/homebrew/bin/zsh /opt/local/bin/zsh; do
    [ -x "$c" ] && candidates+=("$c")
  done
  local p
  p="$(command -v zsh 2>/dev/null || true)"
  if [ -n "$p" ] && [ -x "$p" ]; then
    candidates+=("$p")
  fi
  for c in "${candidates[@]}"; do
    if zsh_module_ok "$c"; then
      ZSH_BIN="$c"
      return 0
    fi
  done
  return 1
}

ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  [ -n "$pkg_mgr" ] || die "git is missing and no package manager was detected."
  log "git is missing — installing via $pkg_mgr…"
  pkg_install git
  need_cmd git
}

ensure_zsh() {
  if find_working_zsh; then
    log "zsh OK: $ZSH_BIN (core modules load)"
    return 0
  fi
  if [ -n "$pkg_mgr" ]; then
    log "zsh is missing or broken (core modules do not load) — installing via $pkg_mgr…"
    pkg_install zsh
    find_working_zsh || die "zsh still not functional after install. Fix manually, e.g.: $SUDO apt-get install -y zsh"
    log "zsh installed and working: $ZSH_BIN"
  else
    die "no working zsh and no package manager detected. Install zsh manually (e.g. 'apt-get install zsh') and re-run."
  fi
}

# ---- Oh My Zsh + plugins + theme --------------------------------------------
ensure_omz() {
  local omz_dir="${HOME}/.oh-my-zsh"
  if [ -d "$omz_dir" ]; then
    log "oh-my-zsh already present: $omz_dir"
    return 0
  fi
  log "installing Oh My Zsh…"
  git clone --depth=1 "$OMZ_URL" "$omz_dir"
}

ensure_plugin() {
  local name="$1" url="$2"
  local dest="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/${name}"
  if [ -d "$dest" ]; then
    log "plugin '$name' already present"
    return 0
  fi
  log "installing plugin '$name'…"
  git clone --depth=1 "$url" "$dest"
}

ensure_p10k() {
  local dest="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/themes/powerlevel10k"
  if [ -d "$dest" ]; then
    log "powerlevel10k already present"
    return 0
  fi
  log "installing powerlevel10k theme…"
  git clone --depth=1 "$P10K_URL" "$dest"
}

# ---- canonical config ---------------------------------------------------------
write_canonical_zshrc() {
  # Single source of truth. If --rc was given, or a `zshrc` file sits next to
  # this script, use that instead of the embedded copy (lets a fork diverge).
  local src
  if [ -n "$CUSTOM_RC_FILE" ] && [ -f "$CUSTOM_RC_FILE" ]; then
    src="$CUSTOM_RC_FILE"
  elif [ -f "${SCRIPT_DIR}/zshrc" ]; then
    src="${SCRIPT_DIR}/zshrc"
  else
    src="$(mktemp)"
    cat > "$src" <<'ZSH_RC_EOF'
# ~/.zshrc — canonical config shipped by dev-setup (github.com/bhataprameya/dev-setup)
# This file is byte-identical on every machine. It auto-adapts at runtime, so
# it works on source-built zsh (under ~/.local), distro zsh (/usr/bin/zsh),
# and Homebrew zsh (macOS) without any per-machine edits.
# Add your own tweaks BELOW the last line, or keep them out of this file.

# ---------------------------------------------------------------------------
# 0. Module discovery (MUST be near the top)
#    A zsh compiled to look in one module path (e.g. /usr/lib/x86_64-linux-gnu/zsh)
#    will fail with "cannot open shared object file: zsh/zle.so" if it was
#    installed elsewhere. Add every user-local module dir we can find, so a
#    source-built zsh works out of the box. No-op on normal installs.
#    `zmodload zsh/zle` resolves to <module_path>/zsh/zle.so, so module_path
#    points at the version dir (…/zsh/5.9) whose `zsh/` subdir holds the .so.
# ---------------------------------------------------------------------------
for _moddir in ${HOME}/.local/lib/*/zsh/*(N) ${HOME}/.local/lib/zsh/*(N); do
  [ -d "$_moddir/zsh" ] && module_path=("$_moddir" $module_path)
done
unset _moddir

# User-local function dirs (source-built zsh under ~/.local). No-op when absent.
# Existence-guarded so normal distro installs never see these paths.
# Autoloadable functions live in per-category subdirs (Completion, Misc, ...),
# so EVERY subdir of $HOME/.local/share/zsh/functions must be on fpath.
for _fdir in \
  ${HOME}/.local/share/zsh/site-functions \
  ${HOME}/.local/share/zsh/functions(N) \
  ${HOME}/.local/share/zsh/functions/*(N/); do
  [ -d "$_fdir" ] && fpath=("$_fdir" $fpath)
done
unset _fdir

# Enable Powerlevel10k instant prompt (keep near the top).
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

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

if [[ -d "$ZSH" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  echo "oh-my-zsh not found at $ZSH — run the dev-setup installer." >&2
fi

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

# Powerlevel10k prompt configuration (identical on every machine).
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
ZSH_RC_EOF
  fi
  echo "$src"
}

install_configs() {
  local src rc_backup
  src="$(write_canonical_zshrc)"

  local dst="${HOME}/.zshrc"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    rc_backup="${dst}.pre-zsh-install.$(date +%Y%m%d-%H%M%S)"
    cp "$dst" "$rc_backup"
    log "backed up existing config to $rc_backup"
  fi
  cp "$src" "$dst"
  log "installed canonical ~/.zshrc"

  # Optional canonical p10k config (byte-identical prompt on every machine).
  if [ -f "${SCRIPT_DIR}/p10k.zsh" ]; then
    cp "${SCRIPT_DIR}/p10k.zsh" "${HOME}/.p10k.zsh"
    log "installed canonical ~/.p10k.zsh"
  fi
}

# ---- default shell ------------------------------------------------------------
current_shell() {
  local user="${USER:-$(id -un)}"
  case "$platform" in
    darwin) dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}' ;;
    *)      getent passwd "$user" 2>/dev/null | cut -d: -f7 ;;
  esac
}

set_default_shell() {
  [ "$CHANGE_SHELL" = 1 ] || { log "skipping default-shell change (--no-shell)"; return 0; }
  command -v chsh >/dev/null 2>&1 || { warn "chsh not available — skipping default-shell change"; return 0; }
  if [ "$ROOT" -ne 1 ] && [ -z "$SUDO" ]; then
    warn "no root and no sudo — skipping default-shell change (run with sudo or use chsh)"
    return 0
  fi

  local user="${USER:-$(id -un)}"
  if [ "$(current_shell)" = "$ZSH_BIN" ]; then
    log "default shell is already $ZSH_BIN"
    return 0
  fi

  # Linux chsh requires the shell to be listed in /etc/shells.
  if [ "$platform" = "linux" ] && ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
    log "adding $ZSH_BIN to /etc/shells…"
    if ! $SUDO sh -c "echo '$ZSH_BIN' >> /etc/shells"; then
      warn "could not update /etc/shells — skipping default-shell change"
      return 0
    fi
  fi

  log "setting default shell to $ZSH_BIN…"
  if [ "$ROOT" -eq 1 ]; then
    chsh -s "$ZSH_BIN" "$user" || warn "chsh failed — set it later with: chsh -s $ZSH_BIN"
  else
    $SUDO chsh -s "$ZSH_BIN" "$user" || warn "chsh failed — set it later with: sudo chsh -s $ZSH_BIN"
  fi
}

# ---- verification --------------------------------------------------------------
verify_shell() {
  log "verifying interactive zsh loads cleanly…"
  local out
  out="$("$ZSH_BIN" -i -c 'true' 2>&1 || true)"
  if printf '%s' "$out" | grep -Eq 'failed to load module|function definition file not found'; then
    warn "interactive zsh reports load failures:"
    printf '%s\n' "$out" | grep -E 'failed to load module|function definition file not found' | head -5
    warn "The active zsh binary ($ZSH_BIN) has wrong compiled-in module/fpath directories."
    warn "If your shell still misbehaves, install a proper system zsh, e.g.  $SUDO apt-get install -y zsh"
  else
    log "interactive zsh loads cleanly."
  fi
}

# ---- main ------------------------------------------------------------------------
main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes)     ASSUME_YES=1 ;;
      --no-shell)   CHANGE_SHELL=0 ;;
      --rc)         shift; CUSTOM_RC_FILE="${1:-}"; [ -n "$CUSTOM_RC_FILE" ] || die "--rc requires a path" ;;
      -h|--help)    usage; exit 0 ;;
      *)            die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done

  detect_platform
  log "platform=$platform distro=${distro:-n/a} pkg_mgr=${pkg_mgr:-none} root=$ROOT"

  ensure_git
  ensure_zsh
  ensure_omz
  ensure_plugin "zsh-autosuggestions" "$AUTOSUGGEST_URL"
  ensure_plugin "zsh-syntax-highlighting" "$SYNTAX_HL_URL"
  ensure_plugin "zsh-completions" "$COMPLETIONS_URL"
  ensure_p10k
  install_configs
  verify_shell
  set_default_shell

  printf '\n\033[1;32mDone.\033[0m Start a new zsh session (or run `zsh`) to pick up the new config.\n'
  printf 'If the prompt looks plain, run `p10k configure` once to tune it.\n'
}

main "$@"
