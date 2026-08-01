# dev-setup

Scripted setup for a development machine. Each tool lives in its own folder with a
self-contained installer, its own tests, and its own README — so you can install just
the piece you want, or add new ones without touching the others.

Everything here is designed to be **portable** (macOS and Linux, glibc and musl),
**idempotent** (safe to re-run), and **non-destructive** (existing configs are backed up).

## Components

| Component | What it does | Install |
|---|---|---|
| [`zsh-install`](zsh-install/) | zsh + Oh My Zsh + Powerlevel10k, with autosuggestions, syntax highlighting, completions, and the MesloLGS NF font | `sh -c "$(curl -fsSL https://raw.githubusercontent.com/bhataprameya/dev-setup/main/zsh-install/install.sh)"` |

More components will be added here over time.

## Usage

Each component is independent. Run its one-liner from the table above, or clone the repo
and run it locally:

```bash
git clone https://github.com/bhataprameya/dev-setup.git
cd dev-setup/zsh-install
./install.sh
```

See each component's README for its options, flags, and rollback instructions.

## Layout

```
dev-setup/
├── README.md          # this index
├── Makefile           # run tests across every component
└── zsh-install/       # one folder per tool
    ├── README.md      # component docs
    ├── install.sh     # the installer
    ├── Makefile       # component tasks (lint / test / stress / e2e)
    ├── .p10k.zsh      # shipped config
    └── test/          # component test suite
```

### Adding a new component

1. Create a folder, e.g. `git-setup/`.
2. Add an idempotent `install.sh` that backs up anything it replaces.
3. Add a `README.md` and a `test/` suite (copy `zsh-install/` as a starting point).
4. Add a row to the component table above.

The top-level `Makefile` discovers component folders automatically, so `make test`
will pick up the new one without any changes.

## Testing

```bash
make test     # run every component's test suite
make lint     # lint every component
make list     # show discovered components
```

Per component:

```bash
cd zsh-install
make test
make stress STRESS_N=100
```

## License

MIT
