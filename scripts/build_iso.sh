#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

usage() {
  cat <<'USAGE'
Build a Rocky installer ISO with an embedded Kickstart using a Dockerized mkksiso.

Usage:
  ./scripts/build_iso.sh -i <input.iso> -k <ks.cfg> -o <output.iso> [-t <tag>]

Args:
  -i  Path to input Rocky ISO (Boot or DVD)
  -k  Path to Kickstart file
  -o  Output ISO filename/path
  -t  Docker image tag (default: rocky-iso-maker)

Example:
  ./scripts/build_iso.sh -i Rocky.iso -k ks.cfg -o Rocky-ks.iso
USAGE
}

IMAGE_TAG="rocky-iso-maker"
INPUT_ISO=""
KS_FILE=""
OUTPUT_ISO=""

while getopts ":i:k:o:t:h" opt; do
  case "$opt" in
    i) INPUT_ISO="$OPTARG" ;;
    k) KS_FILE="$OPTARG" ;;
    o) OUTPUT_ISO="$OPTARG" ;;
    t) IMAGE_TAG="$OPTARG" ;;
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

# Resolve to absolute paths so bind mounts work regardless of cwd or path style
INPUT_ISO_ABS="$(realpath "${INPUT_ISO}")"
KS_FILE_ABS="$(realpath "${KS_FILE}")"
OUTPUT_DIR="$(mkdir -p "$(dirname "${OUTPUT_ISO}")" && realpath "$(dirname "${OUTPUT_ISO}")")"
OUTPUT_NAME="$(basename "${OUTPUT_ISO}")"

# Build the ISO maker image (Dockerfile lives in the repo root)
docker build -t "${IMAGE_TAG}" "${REPO_DIR}"

# Run mkksiso inside the container.
# Mount each file individually to avoid path resolution issues.
# MSYS_NO_PATHCONV prevents Git Bash (Windows) from mangling /work paths.
MSYS_NO_PATHCONV=1 docker run --rm --privileged \
  -v "${INPUT_ISO_ABS}:/work/input.iso:ro" \
  -v "${KS_FILE_ABS}:/work/ks.cfg:ro" \
  -v "${OUTPUT_DIR}:/work/out" \
  "${IMAGE_TAG}" \
  "mkksiso --ks /work/ks.cfg /work/input.iso /work/out/${OUTPUT_NAME}"

echo "Created: ${OUTPUT_ISO}"
