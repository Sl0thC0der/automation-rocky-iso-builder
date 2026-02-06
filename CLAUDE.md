# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

Build an easy-to-deploy Rocky Linux installer ISO for spare hardware that comes up ready for **remote Docker testing**. Local install via ISO/USB (not PXE). After a single unattended boot the machine has SSH, Docker Engine, Podman, Cockpit, fail2ban, and a full DevOps toolset — ready to use over the network.

## Build Commands

### PowerShell (Windows — recommended)
```powershell
.\build.ps1                # with pre-baked RPMs (default)
.\build.ps1 -NoPrebake     # without pre-baking
```

### Git Bash
```bash
./scripts/build_iso.sh -i Rocky-10.1-x86_64-dvd1.iso -k ks.cfg -o output/Rocky-ks.iso -p
```

### Flags
| Flag | Description |
|------|-------------|
| `-i` | Input Rocky ISO (DVD or Boot) |
| `-k` | Kickstart file |
| `-o` | Output ISO path |
| `-t` | Docker image tag (default: `rocky-iso-maker`) |
| `-p` | Pre-bake RPMs into the ISO |
| `-P` | Custom package list file (implies `-p`) |

## Architecture

**Build pipeline:** `build.ps1` → `build_iso.sh` validates inputs → resolves absolute paths → builds Docker image from `Dockerfile` → (optional) downloads RPMs in container → runs `mkksiso` in container → cleans GRUB menu → injects pre-baked RPMs via xorriso → produces bootable ISO.

### File Layout

| File | Purpose |
|------|---------|
| `build.ps1` | PowerShell wrapper for Windows usage |
| `Dockerfile` | Rocky 10 image with `lorax`, `xorriso`, `createrepo_c` |
| `scripts/build_iso.sh` | Main build orchestration (Bash) |
| `scripts/download_rpms.sh` | RPM downloader (runs inside Docker container) |
| `scripts/pkg-list.conf` | Declarative package list with repo sections |
| `kickstart/ks.cfg.example` | Template kickstart (copy to `ks.cfg` and customize) |

### Pre-bake System

The `-p` flag enables RPM pre-baking:
1. `download_rpms.sh` runs in a Docker container, parses `pkg-list.conf` sections (`[rocky]`, `[epel]`, `[docker-ce]`, `[warp]`)
2. Downloads all RPMs + dependencies via `dnf download --resolve --alldeps`
3. Creates repo metadata with `createrepo_c`
4. Injects into ISO at `/prebaked-rpms` via xorriso `-map`
5. Kickstart `%post --nochroot` detects the repo, bind-mounts it into chroot at `/tmp/prebaked-rpms`
6. All `dnf install` commands in `%post` transparently use the local repo first

**Still requires network:** `dnf update/upgrade`, `npm install` (claude-code, codex), `pip3 install yq`

## Expected Usage

1. Place Rocky DVD ISO in repo root (e.g. `Rocky-10.1-x86_64-dvd1.iso`)
2. Copy `kickstart/ks.cfg.example` to `ks.cfg` and customize (user, password, SSH key, timezone)
3. Run `.\build.ps1` (PowerShell) or `./scripts/build_iso.sh` (Bash)
4. Write ISO to USB with Rufus (DD mode) or `dd`
5. Boot target machine — fully unattended install

## Docker / Podman Coexistence Rules

- Install **both** Docker Engine (from Docker's official RHEL repo) and Podman (from Rocky repos)
- **Never install `podman-docker`** — it conflicts with real Docker Engine (socket/CLI collisions)
- Docker uses `/var/run/docker.sock`; Podman socket uses `/run/podman/podman.sock`
- Use `docker ...` for Docker Engine, `podman ...` for Podman

## Kickstart Behavior

- Server environment Rocky install (text mode), DHCP networking, SSH enabled, SELinux enforcing, firewall disabled
- Dynamic partitioning via `%pre`: first disk only, wipe all, EFI + /boot + LVM root (no swap)
- `%post --nochroot`: detects pre-baked RPM repo on ISO, bind-mounts into chroot
- `%post`: full `dnf update`, installs EPEL, removes firewalld, installs Docker/Podman/Cockpit/fail2ban/DevOps tools, hardens SSH, configures kernel tuning, sets up cleanup timers
- **`podman-plugins` does NOT exist on Rocky 10** — do not add it

## Key Considerations

- The container runs with `--privileged` (required for ISO operations)
- Must `rm -f` old output ISO before rebuild (mkksiso refuses to overwrite) — `build.ps1` handles this automatically
- On Windows, `MSYS_NO_PATHCONV=1` is required to prevent Git Bash from mangling container paths
- `%post` must NOT use `set -euo pipefail` — one failed package kills the entire script
- `%post` (chrooted) CANNOT see ISO mount paths — use `%post --nochroot` with bind-mount for ISO access
- Anaconda ISO mount paths: `/run/install/sources/mount-*-cdrom/` (modern RHEL9+) or `/run/install/repo/` (legacy)
- No test suite or CI/CD exists; validation is manual (build ISO, boot VM, verify over SSH)
