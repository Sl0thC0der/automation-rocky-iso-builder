# Rocky Kickstart ISO Builder (Docker + Podman)

This repo produces a **bootable Rocky Linux installer ISO** with an embedded **Kickstart** (`ks.cfg`) by using a **Docker container** that runs `mkksiso` (from `lorax`).

It targets this workflow:

- You have hardware on hand
- You want an unattended Rocky install
- After first boot, the machine has **Podman** *and* **Docker Engine** installed
- "Newest" means newest **available in repos** at install time (Rocky repos for Podman; Docker's official repo for Docker Engine)

## Repo layout

- `Dockerfile` — builds the ISO-builder container image (includes `mkksiso`)
- `kickstart/ks.cfg.example` — Kickstart template (edit to taste)
- `scripts/build_iso.sh` — one-command ISO build wrapper

## Prerequisites

- A Linux machine with Docker installed (to build/run the ISO-builder container)
- An input Rocky ISO (DVD or Boot ISO), e.g. `Rocky-*.iso`
- Enough disk space (ISO extraction + rebuild can require multiple GB)

## Quick start

1) Put a Rocky ISO into the repo directory:

```bash
cp ~/Downloads/Rocky-*.iso ./Rocky.iso
```

2) Copy and edit the Kickstart:

```bash
cp kickstart/ks.cfg.example ks.cfg
# edit ks.cfg (user/password, disk layout, packages, etc.)
```

3) Build the ISO:

```bash
./scripts/build_iso.sh -i Rocky.iso -k ks.cfg -o Rocky-ks.iso
```

4) Write `Rocky-ks.iso` to a USB stick (example; be careful with `/dev/sdX`):

```bash
sudo dd if=Rocky-ks.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

5) Boot your target machine from the USB. Installation should run unattended.

## What the Kickstart does

The provided `kickstart/ks.cfg.example`:

- Installs a minimal Rocky system (minimal environment)
- Enables SSH
- Runs `dnf --refresh update` in `%post` (pull newest packages available at that time)
- Installs:
  - Podman (from Rocky repos)
  - Docker Engine + Buildx + Compose plugin (from Docker's RHEL repo)
- Enables Docker (`systemctl enable docker`) and optionally the Podman API socket (`podman.socket`) so you can target Podman via Docker contexts

## Switching Docker CLI between engines (optional)

If `podman.socket` is enabled, you can create a Docker context that points to Podman's socket:

```bash
docker context create podman --docker "host=unix:///run/podman/podman.sock"
docker context use podman
docker ps
```

Switch back to Docker Engine:

```bash
docker context use default
```

## Notes / safety

- The example Kickstart **wipes the first disk** (`clearpart --all`). Review before using.
- Avoid installing `podman-docker` when you also install real Docker Engine. It can confuse the `docker` CLI/socket expectations.
- Do **not** expose Docker's TCP socket (`2375`) to the internet.

## License

MIT (see `LICENSE`).
