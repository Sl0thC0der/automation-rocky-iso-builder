#!/bin/bash
# Extract PXE boot files (vmlinuz, initrd.img) from Rocky ISO using xorriso in Docker

set -e

# Parse arguments
ISO_PATH="$1"
OUTPUT_DIR="$2"

if [ -z "$ISO_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <iso-path> <output-dir>"
    echo "Example: $0 output/Rocky-ks.iso pxe/tftpboot/rocky"
    exit 1
fi

# Validate ISO exists
if [ ! -f "$ISO_PATH" ]; then
    echo "Error: ISO not found at $ISO_PATH"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get absolute paths (required for Docker bind mounts)
ISO_ABS=$(cd "$(dirname "$ISO_PATH")" && pwd)/$(basename "$ISO_PATH")
OUTPUT_ABS=$(cd "$OUTPUT_DIR" && pwd)

echo "=== Extracting PXE boot files from ISO ==="
echo "  ISO: $ISO_ABS"
echo "  Output: $OUTPUT_ABS"

# Run xorriso in rocky-iso-maker container to extract boot files
# Use existing build image to avoid extra image creation
docker run --rm \
    -v "$ISO_ABS:/work/input.iso:ro" \
    -v "$OUTPUT_ABS:/work/output" \
    rocky-iso-maker \
    -c "xorriso -indev /work/input.iso -osirrox on \
        -extract /images/pxeboot/vmlinuz /work/output/vmlinuz \
        -extract /images/pxeboot/initrd.img /work/output/initrd.img \
        2>&1 | grep -E '(Extracted|extraction)'"

# Verify files were extracted
if [ -f "$OUTPUT_DIR/vmlinuz" ] && [ -f "$OUTPUT_DIR/initrd.img" ]; then
    echo "✓ Extraction complete"
    ls -lh "$OUTPUT_DIR/vmlinuz" "$OUTPUT_DIR/initrd.img"
else
    echo "Error: Boot files not found after extraction"
    exit 1
fi
