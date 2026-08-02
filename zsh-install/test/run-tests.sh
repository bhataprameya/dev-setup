#!/bin/sh
#
# zsh-install test suite
#
#   ./test/run-tests.sh            # run all functional tests once
#   ./test/run-tests.sh --stress 100   # run the install cycle N times
#
# Every test runs against a throwaway $HOME, so nothing on the host is touched.
# If ./test/.mirrors exists (see `make mirrors`), clones come from local mirrors
# so the suite is fast and works offline. Otherwise real upstream URLs are used.

set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIRROR_DIR="$REPO_DIR/test/.mirrors"
INSTALL="$REPO_DIR/install.sh"

pass=0
fail=0
failed_names=""

c_g='\033[1;32m'; c_r='\033[1;31m'; c_y='\033[1;33m'; c_b='\033[1;34m'; c_0='\033[0m'
say()  { printf "${c_b}==>${c_0} %s\n" "$*"; }
tpass() { pass=$((pass+1)); printf "  ${c_g}PASS${c_0} %s\n" "$1"; }
tfail() { fail=$((fail+1)); failed_names="$failed_names\n    - $1: $2"; printf "  ${c_r}FAIL${c_0} %s — %s\n" "$1" "$2"; }
skip()  { printf "  ${c_y}SKIP${c_0} %s — %s\n" "$1" "$2"; }

mktmpd() { mktemp -d 2>/dev/null || mktemp -d -t zshinstall; }

# --------------------------------------------------------------------------- #
# Environment for the installer under test
# --------------------------------------------------------------------------- #
if [ -d "$MIRROR_DIR/ohmyzsh" ]; then
  OFFLINE=1
  export OMZ_REPO="$MIRROR_DIR/ohmyzsh"
  export P10K_REPO="$MIRROR_DIR/powerlevel10k"
  export AUTOSUGGEST_REPO="$MIRROR_DIR/zsh-autosuggestions"
  export SYNTAX_REPO="$MIRROR_DIR/zsh-syntax-highlighting"
  export COMPLETIONS_REPO="$MIRROR_DIR/zsh-completions"
else
  OFFLINE=0
fi
export ASSET_BASE="$REPO_DIR"

# Defaults for tests: never touch the host's shell, fonts, or exec into zsh.
export NO_CHSH=1 NO_FONT=1 NO_EXEC=1 NO_ZSH_INSTALL=1

# Run the installer with an isolated HOME. Extra env may be passed as VAR=VAL.
run_install() { # $1=HOME, rest=env overrides
  _home="$1"; shift
  env HOME="$_home" "$@" sh "$INSTALL" >"$_home/.install.log" 2>&1
}

# Assert the expected files/plugins exist in a given HOME.
check_files() { # $1=HOME -> prints reason on failure
  _h="$1"
  [ -f "$_h/.zshrc" ]                                        || { echo "missing .zshrc"; return 1; }
  grep -q 'powerlevel10k/powerlevel10k' "$_h/.zshrc"          || { echo "theme not set"; return 1; }
  grep -q 'source ~/.p10k.zsh' "$_h/.zshrc"                   || { echo ".p10k.zsh not sourced"; return 1; }
  grep -q 'zsh-autosuggestions' "$_h/.zshrc"                  || { echo "autosuggestions not enabled"; return 1; }
  grep -q 'zsh-syntax-highlighting' "$_h/.zshrc"              || { echo "syntax-highlighting not enabled"; return 1; }
  grep -q '^  git$' "$_h/.zshrc"                              || { echo "git plugin not enabled"; return 1; }
  [ -s "$_h/.p10k.zsh" ]                                      || { echo "missing .p10k.zsh"; return 1; }
  [ -f "$_h/.oh-my-zsh/oh-my-zsh.sh" ]                        || { echo "oh-my-zsh not installed"; return 1; }
  [ -d "$_h/.oh-my-zsh/custom/themes/powerlevel10k" ]         || { echo "p10k theme missing"; return 1; }
  for p in zsh-autosuggestions zsh-syntax-highlighting zsh-completions; do
    [ -d "$_h/.oh-my-zsh/custom/plugins/$p" ]                 || { echo "plugin $p missing"; return 1; }
  done
  return 0
}

# Boot the generated config in a real interactive zsh.
boot_zsh() { # $1=HOME
  env -i HOME="$1" ZDOTDIR="$1" PATH="$PATH" TERM=xterm \
      DISABLE_AUTO_UPDATE=true ZSH_DISABLE_COMPFIX=true \
      zsh -i -c 'exit 0' >/dev/null 2>&1
}

# Build a stub bin dir where the named commands fail (to simulate環境 limits).
stub_dir() { # $@ = command names that should fail
  _d="$(mktmpd)"
  for c in "$@"; do printf '#!/bin/sh\nexit 1\n' > "$_d/$c"; chmod +x "$_d/$c"; done
  echo "$_d"
}

# =========================================================================== #
# Static checks
# =========================================================================== #
say "Static analysis"

t="install.sh parses under multiple shells"
missing=""
for sh_bin in sh dash bash ksh zsh; do
  command -v "$sh_bin" >/dev/null 2>&1 || continue
  "$sh_bin" -n "$INSTALL" 2>/dev/null || missing="$missing $sh_bin"
done
[ -z "$missing" ] && tpass "$t" || tfail "$t" "parse failed under:$missing"

t="no bash-only syntax (pipefail / [[ ]] / \${var//} / BASH_SOURCE)"
if grep -nE 'set -[a-z]*o pipefail|BASH_SOURCE|\$\{[A-Za-z_][A-Za-z_0-9]*//' "$INSTALL" >/dev/null 2>&1; then
  tfail "$t" "found bash-only construct"
else
  tpass "$t"
fi

t="shellcheck clean (POSIX sh dialect)"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -s sh -S warning "$INSTALL" >/dev/null 2>&1; then tpass "$t"; else tfail "$t" "shellcheck reported issues"; fi
else
  skip "$t" "shellcheck not installed"
fi

t="published files leak no machine-specific or secret data"
# Only the files git actually publishes are scanned, and the identifiers are
# derived at runtime — so this script itself contains nobody's personal data.
me="$(id -un 2>/dev/null || true)"
host="$(hostname 2>/dev/null | cut -d. -f1 || true)"
if command -v git >/dev/null 2>&1 && [ -d "$REPO_DIR/.git" ]; then
  tracked="$(git -C "$REPO_DIR" ls-files | grep -v '^test/run-tests.sh$' || true)"
else
  tracked="install.sh README.md Makefile .p10k.zsh"
fi
leak=""
for needle in "$me" "$host"; do
  [ -n "$needle" ] || continue
  for f in $tracked; do
    [ -f "$REPO_DIR/$f" ] || continue
    if grep -niI -- "$needle" "$REPO_DIR/$f" >/dev/null 2>&1; then
      leak="$leak $needle:$f"
    fi
  done
done
# Generic secret-looking assignments / absolute home paths in the shipped config
# (comments are stripped: the upstream p10k template documents /home/username examples).
if [ -n "$leak" ]; then
  tfail "$t" "machine-specific string(s) found ->$leak"
elif sed 's/#.*//' "$REPO_DIR/.p10k.zsh" \
     | grep -qiE '(token|secret|passwd|password|api[_-]?key)[[:space:]]*=[[:space:]]*[^"'"'"'[:space:]]|/(Users|home)/[a-z][a-z0-9_-]*/'; then
  tfail "$t" "possible secret or absolute home path in .p10k.zsh"
else
  tpass "$t"
fi

t="generated .zshrc body is valid zsh"
tmp_zshrc="$(mktmpd)/zshrc"
awk '/^cat > "\$HOME\/\.zshrc" <<.ZSHRC.$/{f=1;next} /^ZSHRC$/{f=0} f' "$INSTALL" > "$tmp_zshrc"
if [ -s "$tmp_zshrc" ] && zsh -n "$tmp_zshrc" 2>/dev/null; then tpass "$t"; else tfail "$t" "zsh -n rejected generated .zshrc"; fi

# =========================================================================== #
# Functional tests
# =========================================================================== #
say "Functional tests (isolated HOME each)"

# --- 1. cold install -------------------------------------------------------- #
t="cold install succeeds and produces a complete setup"
H="$(mktmpd)"
if run_install "$H"; then
  if reason="$(check_files "$H")"; then tpass "$t"; else tfail "$t" "$reason"; fi
else
  tfail "$t" "installer exited nonzero (see $H/.install.log)"
fi

# --- 2. zsh actually boots -------------------------------------------------- #
t="generated config boots in interactive zsh"
if boot_zsh "$H"; then tpass "$t"; else tfail "$t" "zsh -i failed to start"; fi

# --- 3. idempotency --------------------------------------------------------- #
t="re-running is idempotent (no breakage, no duplicate plugin entries)"
if run_install "$H"; then
  dupes="$(grep -c '^  zsh-autosuggestions$' "$H/.zshrc" || true)"
  if reason="$(check_files "$H")" && [ "$dupes" = "1" ]; then tpass "$t"; else tfail "$t" "${reason:-duplicate plugin lines: $dupes}"; fi
else
  tfail "$t" "second run exited nonzero"
fi

# --- 4. existing configs are backed up, not destroyed ----------------------- #
t="pre-existing .zshrc / .p10k.zsh are backed up"
H2="$(mktmpd)"
echo "MY_ORIGINAL_ZSHRC=1" > "$H2/.zshrc"
echo "MY_ORIGINAL_P10K=1"  > "$H2/.p10k.zsh"
if run_install "$H2"; then
  if grep -rqs 'MY_ORIGINAL_ZSHRC' "$H2"/.zshrc.pre-zsh-install.* 2>/dev/null &&
     grep -rqs 'MY_ORIGINAL_P10K'  "$H2"/.p10k.zsh.pre-zsh-install.* 2>/dev/null; then
    tpass "$t"
  else
    tfail "$t" "backup files not found or empty"
  fi
else
  tfail "$t" "installer failed on a HOME with existing config"
fi

# --- 5. chsh failure -> bash handoff --------------------------------------- #
t="when chsh fails, a bash -> zsh handoff is installed"
H3="$(mktmpd)"; STUB="$(stub_dir chsh sudo)"
if env HOME="$H3" PATH="$STUB:$PATH" TEST_RECORDED_SHELL=/bin/bash \
     NO_CHSH=0 NO_FONT=1 NO_EXEC=1 NO_ZSH_INSTALL=1 \
     sh "$INSTALL" >"$H3/.install.log" 2>&1; then
  if grep -q '# >>> zsh-install: launch zsh >>>' "$H3/.bashrc" 2>/dev/null; then tpass "$t"
  else tfail "$t" "handoff block not added to .bashrc"; fi
else
  tfail "$t" "installer exited nonzero when chsh failed"
fi

t="handoff block is valid bash"
if [ -f "$H3/.bashrc" ] && bash -n "$H3/.bashrc" 2>/dev/null; then tpass "$t"; else tfail "$t" "bash -n rejected .bashrc"; fi

t="handoff does NOT trigger for non-interactive shells (no exec loop)"
out="$(env HOME="$H3" timeout 10 bash -c '. "$HOME/.bashrc"; echo SURVIVED' 2>/dev/null || true)"
[ "$out" = "SURVIVED" ] && tpass "$t" || tfail "$t" "non-interactive bash was hijacked (got: $out)"

t="handoff respects ZSH_INSTALL_NO_HANDOFF opt-out"
out="$(env HOME="$H3" ZSH_INSTALL_NO_HANDOFF=1 timeout 10 bash -ic 'echo SURVIVED' 2>/dev/null || true)"
case "$out" in *SURVIVED*) tpass "$t" ;; *) tfail "$t" "opt-out ignored (got: $out)" ;; esac

t="handoff is not duplicated on repeated installs"
env HOME="$H3" PATH="$STUB:$PATH" TEST_RECORDED_SHELL=/bin/bash NO_CHSH=0 NO_FONT=1 NO_EXEC=1 NO_ZSH_INSTALL=1 sh "$INSTALL" >/dev/null 2>&1 || true
n="$(grep -c '# >>> zsh-install: launch zsh >>>' "$H3/.bashrc" 2>/dev/null || echo 0)"
[ "$n" = "1" ] && tpass "$t" || tfail "$t" "expected 1 handoff block, found $n"
rm -rf "$STUB"

# --- 6. flags --------------------------------------------------------------- #
t="NO_CHSH=1 leaves the login shell alone"
H4="$(mktmpd)"
run_install "$H4" >/dev/null 2>&1 || true
if grep -q 'skipping default-shell change' "$H4/.install.log" 2>/dev/null; then tpass "$t"
else tfail "$t" "NO_CHSH was not honored"; fi

t="NO_FONT=1 skips font download"
if grep -q 'skipping font install' "$H4/.install.log" 2>/dev/null; then tpass "$t"
else tfail "$t" "NO_FONT was not honored"; fi

t="NO_ZSH_INSTALL=1 does not invoke a package manager"
if ! grep -qi 'apt-get\|dnf install\|apk add' "$H4/.install.log" 2>/dev/null; then tpass "$t"
else tfail "$t" "attempted package install unexpectedly"; fi

# --- 7. runs under dash (proves POSIX portability at runtime) -------------- #
t="full install runs end-to-end under dash"
if command -v dash >/dev/null 2>&1; then
  H5="$(mktmpd)"
  if env HOME="$H5" NO_CHSH=1 NO_FONT=1 NO_EXEC=1 NO_ZSH_INSTALL=1 \
       ${OMZ_REPO:+OMZ_REPO="$OMZ_REPO"} ${P10K_REPO:+P10K_REPO="$P10K_REPO"} \
       ${AUTOSUGGEST_REPO:+AUTOSUGGEST_REPO="$AUTOSUGGEST_REPO"} \
       ${SYNTAX_REPO:+SYNTAX_REPO="$SYNTAX_REPO"} \
       ${COMPLETIONS_REPO:+COMPLETIONS_REPO="$COMPLETIONS_REPO"} \
       ASSET_BASE="$REPO_DIR" dash "$INSTALL" >"$H5/.install.log" 2>&1; then
    if reason="$(check_files "$H5")"; then tpass "$t"; else tfail "$t" "$reason"; fi
  else
    tfail "$t" "dash run failed (see $H5/.install.log)"
  fi
else
  skip "$t" "dash not installed"
fi

# --- 8. clone-mode install (uses bundled .p10k.zsh, no download) ----------- #
t="install works from a repo clone without network assets"
H6="$(mktmpd)"
if env HOME="$H6" NO_CHSH=1 NO_FONT=1 NO_EXEC=1 NO_ZSH_INSTALL=1 ASSET_BASE="http://127.0.0.1:1/nope" \
     ${OMZ_REPO:+OMZ_REPO="$OMZ_REPO"} ${P10K_REPO:+P10K_REPO="$P10K_REPO"} \
     ${AUTOSUGGEST_REPO:+AUTOSUGGEST_REPO="$AUTOSUGGEST_REPO"} \
     ${SYNTAX_REPO:+SYNTAX_REPO="$SYNTAX_REPO"} \
     ${COMPLETIONS_REPO:+COMPLETIONS_REPO="$COMPLETIONS_REPO"} \
     sh "$INSTALL" >"$H6/.install.log" 2>&1; then
  [ -s "$H6/.p10k.zsh" ] && tpass "$t" || tfail "$t" ".p10k.zsh not installed from clone"
else
  tfail "$t" "clone-mode install failed"
fi

# --- 9. broken zsh detection ------------------------------------------------ #
t="a broken zsh on PATH is ignored; a working system zsh is used"
H7="$(mktmpd)"; STUB="$(stub_dir zsh)"
if env HOME="$H7" PATH="$STUB:$PATH" NO_CHSH=1 NO_FONT=1 NO_EXEC=1 NO_ZSH_INSTALL=1 \
     sh "$INSTALL" >"$H7/.install.log" 2>&1; then
  if grep -q 'zsh: /usr/bin/zsh' "$H7/.install.log"; then tpass "$t"
  else tfail "$t" "installer adopted a broken zsh (see $H7/.install.log)"; fi
else
  tfail "$t" "installer failed when a broken zsh shadowed PATH"
fi
rm -rf "$STUB"

t="only a broken zsh exists: installer refuses and explains (NO_ZSH_INSTALL=1)"
H8="$(mktmpd)"; STUB="$(stub_dir zsh)"
if env HOME="$H8" PATH="$STUB:$PATH" ZSH_CANDIDATES="/nonexistent/bin/zsh" \
     NO_CHSH=1 NO_FONT=1 NO_EXEC=1 NO_ZSH_INSTALL=1 \
     sh "$INSTALL" >"$H8/.install.log" 2>&1; then
  tfail "$t" "installer proceeded with a broken zsh"
else
  if grep -q 'no working zsh found' "$H8/.install.log"; then tpass "$t"
  else tfail "$t" "did not die with a clear message (see $H8/.install.log)"; fi
fi
rm -rf "$STUB"

t="a working zsh outside standard paths is adopted from PATH"
H9="$(mktmpd)"; D="$(mktmpd)"
printf '#!/bin/sh\nexec /usr/bin/zsh "$@"\n' > "$D/zsh"; chmod +x "$D/zsh"
if env HOME="$H9" PATH="$D:$PATH" ZSH_CANDIDATES="/nonexistent/bin/zsh" \
     NO_CHSH=1 NO_FONT=1 NO_EXEC=1 NO_ZSH_INSTALL=1 \
     sh "$INSTALL" >"$H9/.install.log" 2>&1; then
  if grep -qF "zsh: $D/zsh" "$H9/.install.log"; then tpass "$t"
  else tfail "$t" "PATH-only working zsh not adopted (see $H9/.install.log)"; fi
else
  tfail "$t" "install failed when zsh lives only on PATH"
fi
rm -rf "$D"

t="generated .zshrc includes user-local module discovery"
H10="$(mktmpd)"
if run_install "$H10"; then
  if grep -qF 'module_path=("$_moddir" $module_path)' "$H10/.zshrc"; then tpass "$t"
  else tfail "$t" "module discovery block missing from .zshrc"; fi
else
  tfail "$t" "install failed (see $H10/.install.log)"
fi

# =========================================================================== #
# Optional stress mode
# =========================================================================== #
if [ "${1:-}" = "--stress" ]; then
  N="${2:-100}"
  say "Stress: $N full cycles (cold install + re-install + zsh boot)"
  s_pass=0; s_fail=0
  i=1
  while [ "$i" -le "$N" ]; do
    SH="$(mktmpd)"
    if run_install "$SH" && check_files "$SH" >/dev/null &&
       run_install "$SH" && check_files "$SH" >/dev/null && boot_zsh "$SH"; then
      s_pass=$((s_pass+1))
    else
      s_fail=$((s_fail+1)); printf "  ${c_r}iteration %s failed${c_0}\n" "$i"
    fi
    rm -rf "$SH"
    [ $((i % 20)) -eq 0 ] && printf "  ...%s/%s (pass=%s fail=%s)\n" "$i" "$N" "$s_pass" "$s_fail"
    i=$((i+1))
  done
  if [ "$s_fail" -eq 0 ]; then tpass "stress $N/$N cycles"; else tfail "stress" "$s_fail of $N cycles failed"; fi
fi

# =========================================================================== #
# Summary
# =========================================================================== #
printf "\n"
say "Results: $pass passed, $fail failed$( [ "$OFFLINE" = "1" ] && echo "  (offline mirrors)" )"
if [ "$fail" -ne 0 ]; then
  printf "${c_r}Failed tests:${c_0}"; printf "$failed_names\n"
  exit 1
fi
printf "${c_g}All tests passed.${c_0}\n"
