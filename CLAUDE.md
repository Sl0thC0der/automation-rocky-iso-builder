# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

Build an easy-to-deploy Rocky Linux installer ISO for spare hardware that comes up ready for **remote Docker testing**. Local install via ISO/USB (not PXE). After a single unattended boot the machine has SSH, Docker Engine, and Podman — ready to use over the network.

## Build Command

```bash
./scripts/build_iso.sh -i <input.iso> -k <ks.cfg> -o <output.iso> [-t <docker-image-tag>]
```

This builds the Docker image (rockylinux/rockylinux:10 + lorax/xorriso/isomd5sum), then runs `mkksiso` inside a privileged container with files bind-mounted into `/work`.

## Architecture

**Build pipeline:** `build_iso.sh` validates inputs → resolves absolute paths → builds Docker image from `Dockerfile` → runs `mkksiso` in container → produces bootable ISO with embedded kickstart.

- **Dockerfile** — Rocky 10-based image with `lorax`, `xorriso`, `isomd5sum` for ISO manipulation
- **scripts/build_iso.sh** — Bash wrapper (uses `set -euo pipefail`) that orchestrates Docker build and container execution with `--privileged`. Uses `MSYS_NO_PATHCONV=1` for Windows/Git Bash compatibility.
- **kickstart/ks.cfg.example** — Template kickstart (RHEL10 format) that configures minimal Rocky install with both Docker Engine and Podman, user `rocky` in wheel/docker groups, locked root, SELinux enforcing

## Expected Usage

1. Place Rocky ISO in repo root and kickstart as `ks.cfg`
2. Run `build_iso.sh` to generate `Rocky-ks.iso`
3. Write ISO to USB (`dd`) and boot target machine
4. Post-install verification over SSH:
   - `docker run --rm hello-world`
   - `podman run --rm hello-world`
   - `docker compose version`

## Docker / Podman Coexistence Rules

- Install **both** Docker Engine (from Docker's official RHEL repo) and Podman (from Rocky repos)
- **Never install `podman-docker`** — it conflicts with real Docker Engine (socket/CLI collisions)
- Docker uses `/var/run/docker.sock`; Podman socket (optional) uses `/run/podman/podman.sock`
- Use `docker ...` for Docker Engine, `podman ...` for Podman
- Optionally switch Docker CLI to target Podman via Docker contexts:
  ```bash
  docker context create podman --docker "host=unix:///run/podman/podman.sock"
  docker context use podman
  ```
- "Always newest" means: `dnf --refresh update` for Rocky packages; Docker packages from Docker's official repo

## Kickstart Behavior

- Minimal Rocky install (text mode), DHCP networking, SSH enabled, SELinux enforcing
- Partitioning: **wipes first disk entirely** (`clearpart --all`) + autopart with LVM/XFS
- `%post` runs: full `dnf update`, installs Podman, removes `podman-docker`, adds Docker repo, installs Docker Engine + Buildx + Compose, enables Docker daemon, optionally enables `podman.socket`, adds user to docker group

## Key Considerations

- The container runs with `--privileged` (required for ISO operations)
- The Docker base image is `rockylinux/rockylinux:10` (org namespace, not official library)
- User passwords in the kickstart example are plaintext — production use should switch to hashed passwords (`--iscrypted`)
- Do **not** expose Docker's TCP API (2375) publicly; use VPN (e.g. Tailscale) or firewall rules
- On Windows, `MSYS_NO_PATHCONV=1` is required to prevent Git Bash from mangling container paths
- No test suite or CI/CD exists; validation is manual (build ISO, boot, verify installation)
