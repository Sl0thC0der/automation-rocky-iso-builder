#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

usage() {
  cat <<'USAGE'
Build a Rocky installer ISO with an embedded Kickstart using a Dockerized mkksiso.

Usage:
  ./scripts/build_iso.sh -i <input.iso> -k <ks.cfg> -o <output.iso> [-t <tag>] [-p] [-P <pkg-list>]

Args:
  -i  Path to input Rocky ISO (Boot or DVD)
  -k  Path to Kickstart file
  -o  Output ISO filename/path
  -t  Docker image tag (default: rocky-iso-maker)
  -p  Pre-bake RPMs into the ISO (downloads packages at build time)
  -P  Custom package list file (default: scripts/pkg-list.conf, implies -p)

Example:
  ./scripts/build_iso.sh -i Rocky.iso -k ks.cfg -o Rocky-ks.iso
  ./scripts/build_iso.sh -i Rocky.iso -k ks.cfg -o Rocky-ks.iso -p
USAGE
}

IMAGE_TAG="rocky-iso-maker"
INPUT_ISO=""
KS_FILE=""
OUTPUT_ISO=""
PREBAKE=false
PKG_LIST=""

while getopts ":i:k:o:t:pP:h" opt; do
  case "$opt" in
    i) INPUT_ISO="$OPTARG" ;;
    k) KS_FILE="$OPTARG" ;;
    o) OUTPUT_ISO="$OPTARG" ;;
    t) IMAGE_TAG="$OPTARG" ;;
    p) PREBAKE=true ;;
    P) PKG_LIST="$OPTARG"; PREBAKE=true ;;
    h) usage; exit 0 ;;
    :) echo "Missing value for -$OPTARG" >&2; usage; exit 2 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${INPUT_ISO}" || -z "${KS_FILE}" || -z "${OUTPUT_ISO}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${INPUT_ISO}" ]]; then
  echo "Input ISO not found: ${INPUT_ISO}" >&2
  exit 1
fi
if [[ ! -f "${KS_FILE}" ]]; then
  echo "Kickstart not found: ${KS_FILE}" >&2
  exit 1
fi

# Default package list
if [[ -z "${PKG_LIST}" ]]; then
  PKG_LIST="${SCRIPT_DIR}/pkg-list.conf"
fi
if [[ "${PREBAKE}" == true && ! -f "${PKG_LIST}" ]]; then
  echo "Package list not found: ${PKG_LIST}" >&2
  exit 1
fi

# Resolve to absolute paths so bind mounts work regardless of cwd or path style
INPUT_ISO_ABS="$(realpath "${INPUT_ISO}")"
KS_FILE_ABS="$(realpath "${KS_FILE}")"
OUTPUT_DIR="$(mkdir -p "$(dirname "${OUTPUT_ISO}")" && realpath "$(dirname "${OUTPUT_ISO}")")"
OUTPUT_NAME="$(basename "${OUTPUT_ISO}")"

# Build the ISO maker image (Dockerfile lives in the repo root)
docker build -t "${IMAGE_TAG}" "${REPO_DIR}"

# ── Pre-bake RPMs (optional) ────────────────────────────────────────
PREBAKE_DIR="${REPO_DIR}/prebaked-rpms"
if [[ "${PREBAKE}" == true ]]; then
  echo "=== Pre-baking RPMs ==="
  PKG_LIST_ABS="$(realpath "${PKG_LIST}")"
  DOWNLOAD_SCRIPT_ABS="$(realpath "${SCRIPT_DIR}/download_rpms.sh")"

  # Clean previous prebake
  rm -rf "${PREBAKE_DIR}"
  mkdir -p "${PREBAKE_DIR}"

  MSYS_NO_PATHCONV=1 docker run --rm \
    --name rocky-rpm-downloader \
    --entrypoint bash \
    -v "${PKG_LIST_ABS}:/work/pkg-list.conf:ro" \
    -v "${DOWNLOAD_SCRIPT_ABS}:/work/download_rpms.sh:ro" \
    -v "${PREBAKE_DIR}:/work/prebaked-rpms" \
    "${IMAGE_TAG}" \
    -c 'bash /work/download_rpms.sh /work/pkg-list.conf /work/prebaked-rpms'

  RPM_COUNT=$(find "${PREBAKE_DIR}" -name '*.rpm' | wc -l)
  echo "=== Pre-baked ${RPM_COUNT} RPMs ==="
fi

# ── Build the ISO ───────────────────────────────────────────────────
# Run mkksiso inside the container, then clean up the GRUB menu.
# Mount each file individually to avoid path resolution issues.
# MSYS_NO_PATHCONV prevents Git Bash (Windows) from mangling /work paths.
# --entrypoint overrides the Dockerfile's ENTRYPOINT to avoid double-bash nesting.

# Build volume mounts array
DOCKER_VOLS=(
  -v "${INPUT_ISO_ABS}:/work/input.iso:ro"
  -v "${KS_FILE_ABS}:/work/ks.cfg:ro"
  -v "${OUTPUT_DIR}:/work/out"
)
if [[ "${PREBAKE}" == true && -d "${PREBAKE_DIR}" ]]; then
  PREBAKE_DIR_ABS="$(realpath "${PREBAKE_DIR}")"
  DOCKER_VOLS+=(-v "${PREBAKE_DIR_ABS}:/work/prebaked-rpms:ro")
fi

# Build the xorriso -map arguments for GRUB + optional RPM injection
XORRISO_MAPS='-map "$TMPDIR/grub-efi.cfg" /EFI/BOOT/grub.cfg -map "$TMPDIR/grub-boot.cfg" /boot/grub2/grub.cfg'
if [[ "${PREBAKE}" == true ]]; then
  XORRISO_MAPS+=' -map /work/prebaked-rpms /prebaked-rpms'
fi

MSYS_NO_PATHCONV=1 docker run --rm --privileged \
  --name rocky-iso-builder \
  --entrypoint bash \
  "${DOCKER_VOLS[@]}" \
  "${IMAGE_TAG}" \
  -c '
set -euo pipefail

# 1) Build the kickstart ISO
mkksiso --ks /work/ks.cfg -c "inst.text console=tty0 rd.live.check=0" /work/input.iso /work/out/'"${OUTPUT_NAME}"'

# 2) Clean GRUB menu: keep only "Install", no delay
ISO="/work/out/'"${OUTPUT_NAME}"'"
TMPDIR=$(mktemp -d)

xorriso -indev "$ISO" -osirrox on \
    -extract /EFI/BOOT/grub.cfg "$TMPDIR/grub-efi.cfg" \
    -extract /boot/grub2/grub.cfg "$TMPDIR/grub-boot.cfg"

for f in "$TMPDIR/grub-efi.cfg" "$TMPDIR/grub-boot.cfg"; do
    # Remove "Test this media" entry
    sed -i "/^menuentry.*Test this media/,/^}/d" "$f"
    # Remove "FIPS mode" entry
    sed -i "/^menuentry.*FIPS mode/,/^}/d" "$f"
    # Remove Troubleshooting submenu (from submenu line to closing brace)
    sed -i "/^submenu/,/^}/d" "$f"
    # Boot immediately, no delay
    sed -i "s/^set timeout=.*/set timeout=0/" "$f"
    sed -i "s/^set default=.*/set default=\"0\"/" "$f"
done

# 3) Repack ISO: GRUB configs + optional pre-baked RPMs in a single xorriso pass
mv "$ISO" "${ISO}.tmp"
xorriso -indev "${ISO}.tmp" -outdev "$ISO" \
    -boot_image any replay \
    '"${XORRISO_MAPS}"'

rm -f "${ISO}.tmp"
rm -rf "$TMPDIR"

# 4) Re-implant ISO checksum (xorriso repack invalidates the original)
implantisomd5 "$ISO"
echo "GRUB menu cleaned, ISO checksum implanted"
'

echo "Created: ${OUTPUT_ISO}"
if [[ "${PREBAKE}" == true ]]; then
  echo "  (includes pre-baked RPM repo at /prebaked-rpms on the ISO)"
fi
