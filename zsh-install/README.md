# zsh-install

Part of [dev-setup](../README.md).

A one-command, portable setup for a fast, good-looking zsh: **Oh My Zsh + Powerlevel10k** with autosuggestions, syntax highlighting, and completions — plus the recommended **MesloLGS NF** font.

Works on **macOS and Linux** (glibc *and* musl/Alpine), as **root or a normal user**, under any POSIX shell (`sh`/`dash`/`ash`/`bash`/`zsh`) — no bash required. It's **idempotent**: re-running updates everything in place, and any existing config is backed up first.

## Quick install (one-liner)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install/install.sh)"
```

Or with `wget`:

```bash
sh -c "$(wget -qO- https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install/install.sh)"
```

The installer sets zsh as your **default shell** and **launches zsh** for you when it finishes — so the setup is live immediately. The only manual step is a one-time terminal setting: choose the font **MesloLGS NF** so the prompt icons render (a shell script can't change your terminal app's font — that lives in the emulator's own preferences).

## What it installs

- **zsh** — installed automatically if missing (via `apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`, or `brew`).
- **[Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)** — framework, cloned to `~/.oh-my-zsh`.
- **[Powerlevel10k](https://github.com/romkatv/powerlevel10k)** — theme, with a pre-tuned `~/.p10k.zsh` (user@host on the left, full path, full git branch, clean right side, instant prompt).
- **Plugins**: `git`, `z`, `sudo`, `colored-man-pages`, `command-not-found`, `copypath`, `dirhistory`, `extract`, plus external:
  - [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) (grey ghost-text suggestions)
  - [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)
  - [zsh-completions](https://github.com/zsh-users/zsh-completions)
- **[MesloLGS NF](https://github.com/romkatv/powerlevel10k#fonts)** font (`~/Library/Fonts` on macOS, `~/.local/share/fonts` on Linux).
- A **clean, minimal `~/.zshrc`** — sensible history/completion defaults, portable colored `ls`, generic aliases, and lazy-loaded `nvm` (if you have it) so startup stays fast. No machine-specific junk.

## Idempotent & safe

- Existing `~/.zshrc` and `~/.p10k.zsh` are moved to `*.pre-zsh-install.<timestamp>` before new ones are written.
- Already-installed Oh My Zsh, theme, and plugins are updated (`git pull`) rather than duplicated.
- The default-shell change (`chsh`) runs only in an interactive terminal; otherwise it prints the command to run.

## Options

Set these as environment variables before the one-liner if needed:

| Variable | Effect |
|---|---|
| `NO_CHSH=1` | Don't change your login shell |
| `NO_EXEC=1` | Don't auto-launch zsh at the end |
| `NO_FONT=1` | Don't install the MesloLGS NF font |
| `NO_ZSH_INSTALL=1` | Don't try to install zsh via a package manager |
| `NO_BASH_HANDOFF=1` | Don't add the bash → zsh handoff fallback |
| `ALL_USERS=1` | Also set up **every real user + root** (needs root/sudo) |

Example:

```bash
NO_CHSH=1 sh -c "$(curl -fsSL https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install/install.sh)"
```

## Setting up every user (including root)

By default the installer only touches the user who runs it. To give **root and every real
login account** the same zsh setup in one shot:

```bash
sudo ALL_USERS=1 sh -c "$(curl -fsSL https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install/install.sh)"
```

This copies the Oh My Zsh tree and both config files into each user's home, fixes ownership,
and points their login shell at zsh. Service/system accounts (`nologin`, `/bin/false`, etc.)
are always skipped so daemons keep working. Existing per-user configs are backed up first.

It is opt-in on purpose: changing every account's login shell is a system-wide change, so it
shouldn't happen silently to anyone running a `curl | sh` one-liner.

## If the login shell can't be changed

On managed or containerised hosts `chsh` is sometimes blocked or reverted. In that case the
installer adds a small guarded block to `~/.bashrc` that hands off from an interactive bash
login to zsh, so new terminals still start zsh. It never fires for non-interactive shells
or scripts, and `ZSH_INSTALL_NO_HANDOFF=1` disables it for a single session.

## Development & testing

```bash
make help      # list targets
make lint      # shellcheck (POSIX sh) + parse under sh/dash/bash/ksh/zsh
make test      # full functional suite in throwaway HOMEs
make stress STRESS_N=100   # N cold-install + re-install + zsh-boot cycles
make e2e       # verify the published one-liner against the live repo
make docker-test           # run on real Debian/Ubuntu/Alpine/Fedora, root + non-root
```

The suite (`test/run-tests.sh`) covers: multi-shell parsing, POSIX compliance, no bash-only
syntax, no personal data in the shipped config, cold install, idempotent re-install, backup
of pre-existing configs, booting a real interactive zsh, the `chsh`-failure handoff (including
its non-interactive and no-loop guards), every `NO_*` flag, a full run under `dash`, and
clone-mode install with no network assets.

## Manual install (clone)

```bash
git clone https://github.com/bhataprameya/dev-setup.git
cd dev-setup/zsh-install
./install.sh
```

Running from a clone uses the bundled `.p10k.zsh` directly (no download needed).

## Set the terminal font

The prompt uses icons that need a Nerd Font:

- **macOS Terminal**: Settings → Profiles → Text → Font → **MesloLGS NF**
- **iTerm2**: Settings → Profiles → Text → Font → **MesloLGS NF**
- **VS Code**: set `"terminal.integrated.fontFamily": "MesloLGS NF"`
- **GNOME Terminal / others**: pick **MesloLGS NF** in the profile font setting

## Uninstall / rollback

Your previous files were backed up. To restore them:

```bash
# find the backups
ls -1 ~/.zshrc.pre-zsh-install.* ~/.p10k.zsh.pre-zsh-install.* 2>/dev/null
# restore the most recent
cp "$(ls -t ~/.zshrc.pre-zsh-install.* | head -1)" ~/.zshrc
cp "$(ls -t ~/.p10k.zsh.pre-zsh-install.* | head -1)" ~/.p10k.zsh
exec zsh
```

To remove Oh My Zsh entirely: `rm -rf ~/.oh-my-zsh`.

## License

MIT
