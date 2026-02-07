# Contributing

## Development Setup

1. **Docker Desktop** running (Windows or Linux)
2. **Git Bash** (comes with Git for Windows) or any Bash shell
3. A Rocky Linux DVD ISO (e.g. `Rocky-10.1-x86_64-dvd1.iso`)

## Commit Messages

This project follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

### Format

```
<type>: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `chore` | Build process, tooling, or dependency changes |
| `ci` | CI/CD configuration |

### Examples

```
feat: add pre-baked RPM support for offline installs
fix: resolve LVM VG name conflict on reinstall
docs: update README with build options
chore: add .editorconfig
```

## Branch Naming

```
<type>/<short-description>
```

Examples: `feat/add-pxe-support`, `fix/usb-detection`, `docs/update-readme`

## Shell Script Standards

- Use `#!/bin/bash` shebang
- Use `set -euo pipefail` in build scripts (but **never** in kickstart `%post`)
- 2-space indentation
- Quote all variable expansions: `"${var}"` not `$var`
- Use `[[ ]]` for conditionals (Bash-specific)
- Add `|| true` to non-critical commands in kickstart `%post` sections

## Validation

There is no automated test suite. Validation is manual:

1. Build the ISO: `.\build.ps1`
2. Boot it on a VM or bare-metal machine
3. Verify over SSH that all services are running

## Rocky 10 Package Gotchas

Before adding packages to `scripts/pkg-list.conf` or `kickstart/ks.cfg.example`, verify the package name exists on Rocky 10:

- `iotop` is `iotop-c`
- `cockpit-networkmanager`, `cockpit-selinux`, `cockpit-sosreport` don't exist (merged into `cockpit-system`)
- `podman-plugins` does not exist
