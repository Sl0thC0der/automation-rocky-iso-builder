# Rocky Kickstart ISO Builder

Produces a **bootable Rocky Linux installer ISO** with an embedded Kickstart and optional **pre-baked RPM packages**. After a single unattended boot, the machine has SSH, Docker Engine, Podman, Cockpit, fail2ban, and a full DevOps toolset — ready to use over the network.

## Repo Layout

```
build.ps1                    # PowerShell wrapper (Windows)
Dockerfile                   # ISO-builder container image
kickstart/ks.cfg.example     # Kickstart template (copy to ks.cfg)
scripts/
  build_iso.sh               # Main build script (Bash)
  download_rpms.sh           # RPM downloader for pre-baking
  pkg-list.conf              # Package list (edit to add/remove packages)
```

## Prerequisites

- **Docker Desktop** running
- **Git Bash** (comes with Git for Windows)
- A Rocky Linux DVD ISO (e.g. `Rocky-10.1-x86_64-dvd1.iso`)

## Quick Start

1. Place a Rocky ISO in the repo root:
   ```
   Rocky-10.1-x86_64-dvd1.iso
   ```

2. Copy and customize the kickstart:
   ```powershell
   cp kickstart/ks.cfg.example ks.cfg
   # Edit ks.cfg: change user/password, SSH key, keyboard, timezone
   ```

3. Build the ISO:
   ```powershell
   .\build.ps1
   ```

   Or from Git Bash:
   ```bash
   ./scripts/build_iso.sh -i Rocky-10.1-x86_64-dvd1.iso -k ks.cfg -o output/Rocky-ks.iso
   ```

4. Write to USB with **Rufus** (DD mode) or **balenaEtcher**, then boot your target machine.

## Build Options

### PowerShell
```powershell
.\build.ps1                                          # Default: no pre-bake (fresh packages from internet)
.\build.ps1 -Prebake                                 # Pre-bake RPMs into ISO (faster install, larger ISO)
.\build.ps1 -InputISO "Rocky-10.1-x86_64-dvd1.iso"  # Custom input ISO
.\build.ps1 -Kickstart "my-ks.cfg"                   # Custom kickstart
```

### Bash
```bash
./scripts/build_iso.sh -i <input.iso> -k <ks.cfg> -o <output.iso> [-p] [-P <pkg-list>]
```

| Flag | Description |
|------|-------------|
| `-i` | Input Rocky ISO |
| `-k` | Kickstart file |
| `-o` | Output ISO path |
| `-p` | Pre-bake RPMs into the ISO |
| `-P` | Custom package list file (implies `-p`) |
| `-t` | Docker image tag (default: `rocky-iso-maker`) |

## Pre-baked RPMs

The `-p` flag (or `.\build.ps1 -Prebake`) downloads all packages from `scripts/pkg-list.conf` at build time and embeds them in the ISO. At install time, the kickstart detects and uses them automatically — most packages install from the local ISO instead of downloading.

**Packages are organized by repo in `pkg-list.conf`:**
- `[rocky]` — DevOps tools, Podman, Cockpit, firmware, security tools
- `[epel]` — fail2ban, epel-release
- `[docker-ce]` — Docker Engine, CLI, Buildx, Compose
- `[warp]` — Warp terminal

To add or remove packages, edit `scripts/pkg-list.conf` and rebuild.

**ISO size:** ~9.5 GB with pre-bake (vs ~8.6 GB without). Fits on a 16 GB USB.

## What Gets Installed

| Category | Packages |
|----------|----------|
| Container engines | Docker Engine, Podman, Buildah, Skopeo |
| Docker extras | Compose, Buildx, rootless extras |
| Podman extras | podman-compose, podman-remote, Netavark, passt |
| Web console | Cockpit + storage/packagekit/podman modules |
| Security | fail2ban (nftables), SELinux enforcing, SSH hardening, auditd, firewalld masked |
| DevOps tools | git, vim, tmux, htop, jq, ansible-core, nmap, strace, tcpdump, iotop-c |
| AI tools | Claude Code, Codex (via npm) |
| Terminal | Warp terminal |
| Monitoring | Cockpit, sysstat, SNMP, persistent journald |
| Maintenance | dnf-automatic (security updates), weekly Docker/Podman prune timers |

## Kickstart Details

- **Server environment** install (cmdline mode), DHCP networking, SSH enabled, SELinux enforcing
- **Dynamic partitioning** via `%pre`: auto-detects first disk, EFI + /boot + 100% LVM root, no swap
- **Boot media detection**: safely skips installer media (dd-written USB, Ventoy, CD/DVD) when wiping disks; PXE has no media so all disks are wiped
- **Wipes all non-installer disks** — review `ks.cfg` before use
- **Hardened SSH**: key auth + password fallback, root login disabled, fail2ban (3 attempts / 1h ban)
- **Docker + Podman coexistence**: both installed, no `podman-docker` conflict
- **Firewalld masked** (not removed — removing cascades and breaks fail2ban); nftables used directly
- **Password change on first login** via `/etc/profile.d/` script (only on interactive terminals, doesn't block SSH key auth or non-interactive commands)
- **Hostname from DHCP**: NetworkManager configured to accept hostname from DHCP option 12

## Build Performance

The build uses a RAM-backed tmpfs for intermediate ISO operations, reducing build time from ~11 minutes to ~5 minutes on Docker Desktop (Windows/WSL2).

## Notes

- Passwords in `ks.cfg.example` are plaintext — use `--iscrypted` with hashed passwords for production
- Do not expose Docker TCP API (2375) publicly
- The Docker build container runs with `--privileged` (required for ISO operations)
- `inst.sshd` is enabled on the installer kernel cmdline for debugging — remove for production

## License

MIT (see `LICENSE`).
