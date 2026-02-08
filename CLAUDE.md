# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

Build an easy-to-deploy Rocky Linux installer ISO for spare hardware that comes up ready for **remote Docker testing**. Local install via ISO/USB (not PXE). After a single unattended boot the machine has SSH, Docker Engine, Podman, Cockpit, fail2ban, and a full DevOps toolset — ready to use over the network.

## Build Commands

### PowerShell (Windows — recommended)
```powershell
.\build.ps1                # default: no pre-bake (fresh packages from internet)
.\build.ps1 -Prebake       # pre-bake RPMs into ISO for offline/faster installs
```

### Git Bash
```bash
./scripts/build_iso.sh -i Rocky-10.1-x86_64-dvd1.iso -k ks.cfg -o output/Rocky-ks.iso
./scripts/build_iso.sh -i Rocky-10.1-x86_64-dvd1.iso -k ks.cfg -o output/Rocky-ks.iso -p  # with pre-bake
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

**Build pipeline:** `build.ps1` → `build_iso.sh` validates inputs → builds Docker image (`DOCKER_BUILDKIT=1`) → (optional) downloads RPMs in container → runs `mkksiso` writing to tmpfs (RAM) → cleans GRUB menu → repacks ISO with xorriso (reads from tmpfs) → implants checksum → writes final ISO to output.

### File Layout

| File | Purpose |
|------|---------|
| `build.ps1` | PowerShell wrapper for Windows (default: no prebake, `-Prebake` to opt in) |
| `Dockerfile` | Rocky 10 image with `lorax`, `xorriso`, `isomd5sum`, `createrepo_c` |
| `scripts/build_iso.sh` | Main build orchestration (Bash, uses tmpfs for intermediate ISO) |
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

**Still requires network:** `dnf update/upgrade`, `pip3 install yq`

## Expected Usage

1. Place Rocky DVD ISO in repo root (e.g. `Rocky-10.1-x86_64-dvd1.iso`)
2. Copy `kickstart/ks.cfg.example` to `ks.cfg` and customize (user, password, SSH key, timezone)
3. Run `.\build.ps1` (PowerShell) or `./scripts/build_iso.sh` (Bash)
4. Write ISO to USB with Rufus (DD mode) or `dd`
5. Boot target machine — fully unattended install

**Alternative: PXE Network Boot**

Instead of USB/DVD, serve the ISO over the network:

```powershell
# Default mode (requires DHCP configuration)
.\pxe\start_pxe_server.ps1

# Proxy mode (fully automated, no DHCP config needed)
.\pxe\start_pxe_server.ps1 -ProxyDHCP
```

Then PXE boot target machines. See `README-PXE.md` for setup instructions.

## Docker / Podman Coexistence Rules

- Install **both** Docker Engine (from Docker's official RHEL repo) and Podman (from Rocky repos)
- **Never install `podman-docker`** — it conflicts with real Docker Engine (socket/CLI collisions)
- Docker uses `/var/run/docker.sock`; Podman socket uses `/run/podman/podman.sock`
- Use `docker ...` for Docker Engine, `podman ...` for Podman

## Kickstart Behavior

- Server environment Rocky install (cmdline mode), DHCP networking, SSH enabled, SELinux enforcing
- Dynamic partitioning via `%pre`: first disk only, wipe all, EFI + /boot + LVM root (no swap)
- Boot media detection in `%pre`: skips dd-written USB (iso9660), Ventoy (VTOYEFI/Ventoy labels), CD/DVD (not in list-harddrives); PXE has no media so all disks are wiped
- `%post --nochroot`: detects pre-baked RPM repo on ISO, bind-mounts into chroot
- `%post`: full `dnf update`, installs EPEL+CRB, installs Docker/Podman/Cockpit/fail2ban/DevOps tools, hardens SSH, configures kernel tuning, sets up cleanup timers
- Firewalld is **masked** (not removed — `dnf remove firewalld` cascades and removes fail2ban); fail2ban uses `nftables-allports` (native nftables)
- Hostname set from DHCP via `hostname-mode=dhcp` in NetworkManager config
- Password change script has `[ -t 0 ]` guard — only fires on interactive terminals
- **GPU auto-detection**: Detects AMD/Intel/NVIDIA GPUs and installs appropriate drivers automatically
  - **AMD APU:** amdgpu driver, Vulkan, VDPAU (auto-configured)
  - **Intel iGPU:** i915 driver with GuC/HuC, Vulkan, VA-API (auto-configured)
  - **NVIDIA GPU:** Proprietary nvidia driver from RPMFusion, CUDA support (auto-configured)
  - Disables simpledrm via kernel parameter, creates `/dev/dri/renderD128` for GPU compute
  - NVIDIA akmod compiles on first boot (2-5 minutes), reboot recommended after driver compilation

### Rocky 10 Package Gotchas

- `iotop` → `iotop-c` (C reimplementation)
- `cockpit-networkmanager`, `cockpit-selinux`, `cockpit-sosreport` → don't exist (merged into `cockpit-system`)
- `npm` → installed as `nodejs-npm` (bundled with `nodejs`); `rpm -q npm` fails but `which npm` works
- `podman-plugins` does NOT exist on Rocky 10

## Key Considerations

- The container runs with `--privileged` (required for ISO operations)
- Must `rm -f` old output ISO before rebuild (mkksiso refuses to overwrite) — `build.ps1` handles this automatically
- On Windows, `MSYS_NO_PATHCONV=1` is required to prevent Git Bash from mangling container paths
- `%post` must NOT use `set -euo pipefail` — one failed package kills the entire script
- `%post` (chrooted) CANNOT see ISO mount paths — use `%post --nochroot` with bind-mount for ISO access
- Anaconda ISO mount paths: `/run/install/sources/mount-*-cdrom/` (modern RHEL9+) or `/run/install/repo/` (legacy)
- Do NOT use `cdrom` directive or `inst.repo=cdrom` — both only scan optical `/dev/sr*`, not USB
- `inst.sshd` is on kernel cmdline for debugging — **remove for production** (TODO)
- No test suite or CI/CD exists; validation is manual (build ISO, boot, verify over SSH)
