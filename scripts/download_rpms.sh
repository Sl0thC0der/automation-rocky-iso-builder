#!/usr/bin/env bash
# download_rpms.sh — Runs inside the Docker build container.
# Parses pkg-list.conf, enables required repos, downloads all RPMs
# with dependencies, and creates a local repo with createrepo_c.
set -euo pipefail

PKG_LIST="${1:?Usage: download_rpms.sh <pkg-list.conf> <output-dir>}"
OUT_DIR="${2:?Usage: download_rpms.sh <pkg-list.conf> <output-dir>}"

mkdir -p "${OUT_DIR}"

# ── Parse pkg-list.conf into per-section package arrays ──────────────
declare -A SECTION_PKGS
CURRENT_SECTION=""

while IFS= read -r line; do
    # Strip comments and whitespace
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
        CURRENT_SECTION="${BASH_REMATCH[1]}"
        SECTION_PKGS["$CURRENT_SECTION"]=""
    elif [[ -n "$CURRENT_SECTION" ]]; then
        if [[ -n "${SECTION_PKGS[$CURRENT_SECTION]}" ]]; then
            SECTION_PKGS["$CURRENT_SECTION"]+=" $line"
        else
            SECTION_PKGS["$CURRENT_SECTION"]="$line"
        fi
    fi
done < "${PKG_LIST}"

# ── Enable additional repos needed for download ─────────────────────

# EPEL
dnf -y install epel-release
dnf -y install dnf-plugins-core

# CRB (needed by some EPEL deps)
dnf config-manager --set-enabled crb || true

# Docker CE repo
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

# Warp repo
rpm --import https://releases.warp.dev/linux/keys/warp.asc || true
cat > /etc/yum.repos.d/warp.repo << 'WARP'
[warpdotdev]
name=Warp terminal
baseurl=https://releases.warp.dev/linux/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://releases.warp.dev/linux/keys/warp.asc
WARP

# ── Download RPMs per section ───────────────────────────────────────
TOTAL=0

for section in "${!SECTION_PKGS[@]}"; do
    pkgs="${SECTION_PKGS[$section]}"
    [[ -z "$pkgs" ]] && continue

    echo "=== Downloading [${section}]: ${pkgs} ==="

    # dnf download --resolve pulls the package + all missing deps
    # --alldeps ensures we get everything needed for an offline install
    # shellcheck disable=SC2086
    dnf download --resolve --alldeps \
        --destdir="${OUT_DIR}" \
        ${pkgs} || {
            echo "WARNING: Some packages in [${section}] failed to download" >&2
        }
done

# ── Count and create repo metadata ──────────────────────────────────
TOTAL=$(find "${OUT_DIR}" -name '*.rpm' | wc -l)
echo "=== Downloaded ${TOTAL} RPMs ==="

if [[ "$TOTAL" -eq 0 ]]; then
    echo "ERROR: No RPMs downloaded, aborting" >&2
    exit 1
fi

echo "=== Creating repo metadata ==="
createrepo_c "${OUT_DIR}"

echo "=== Pre-bake complete: ${TOTAL} RPMs in ${OUT_DIR} ==="
