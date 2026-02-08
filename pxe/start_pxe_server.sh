#!/bin/bash
# Rocky PXE Boot Server Launcher (Bash version)
# Starts a containerized TFTP + HTTP server for network installation

set -e

# Default parameters
ISO="output/Rocky-ks.iso"
PORT=80
PROXY_DHCP=false
CONTAINER_NAME="rocky-pxe-server"
SERVER_IP=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Helper functions
header() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
info() { echo -e "  ${GRAY}$1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warning() { echo -e "${YELLOW}! $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--iso) ISO="$2"; shift 2 ;;
        -p|--port) PORT="$2"; shift 2 ;;
        --proxy-dhcp) PROXY_DHCP=true; shift ;;
        --server-ip) SERVER_IP="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -i, --iso PATH         ISO path (default: output/Rocky-ks.iso)"
            echo "  -p, --port PORT        HTTP port (default: 80)"
            echo "  --proxy-dhcp           Enable DHCP proxy mode"
            echo "  --server-ip IP         Server IP (auto-detect if omitted)"
            echo "  -h, --help             Show this help"
            exit 0
            ;;
        *) error "Unknown option: $1" ;;
    esac
done

header "Rocky PXE Server"
info "ISO: $ISO"

# Validate prerequisites
info "Checking prerequisites..."

# Check Docker
if ! docker version &>/dev/null; then
    error "Docker is not running. Please start Docker."
fi
success "Docker is running"

# Validate ISO exists
if [ ! -f "$ISO" ]; then
    error "ISO not found at $ISO\nBuild the ISO first with: ./build.ps1 or ./scripts/build_iso.sh"
fi
success "ISO found"

# Build PXE server image if not exists
if ! docker images rocky-pxe-server -q | grep -q .; then
    header "Building PXE server image"
    DOCKER_BUILDKIT=1 docker build -t rocky-pxe-server -f pxe/Dockerfile.pxe pxe/
    success "Image built"
else
    success "PXE server image exists"
fi

# Extract boot files if not present
VMLINUZ_PATH="pxe/tftpboot/rocky/vmlinuz"
INITRD_PATH="pxe/tftpboot/rocky/initrd.img"

if [ ! -f "$VMLINUZ_PATH" ] || [ ! -f "$INITRD_PATH" ]; then
    header "Extracting boot files from ISO"
    ./pxe/extract_boot_files.sh "$ISO" "pxe/tftpboot/rocky"
    success "Boot files extracted"
else
    success "Boot files already extracted"
fi

# Auto-detect host IP if not provided
if [ -z "$SERVER_IP" ]; then
    info "Auto-detecting host IP..."

    # Detect platform
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        SERVER_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
    else
        # Linux
        SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    fi

    if [ "$SERVER_IP" = "127.0.0.1" ]; then
        warning "Could not auto-detect IP, using 127.0.0.1"
    else
        success "Detected IP: $SERVER_IP"
    fi
fi

# Update PXE boot menu with server IP
info "Configuring PXE boot menu..."
sed "s/PXE_SERVER_IP/$SERVER_IP/g" pxe/config/pxelinux.cfg/default > pxe/tftpboot/pxelinux.cfg/default
success "Boot menu configured with IP $SERVER_IP"

# Stop existing container if running
if docker ps -a -q -f name=$CONTAINER_NAME | grep -q .; then
    info "Stopping existing container..."
    docker stop $CONTAINER_NAME &>/dev/null || true
    docker rm $CONTAINER_NAME &>/dev/null || true
fi

# Prepare Docker run arguments
OUTPUT_DIR=$(cd output && pwd)
TFTPBOOT_DIR=$(cd pxe/tftpboot && pwd)

DOCKER_ARGS=(
    "run" "-d"
    "--name" "$CONTAINER_NAME"
    "--network" "host"
)

# Add DHCP proxy mode if requested
if [ "$PROXY_DHCP" = true ]; then
    DOCKER_ARGS+=("-e" "PROXY_DHCP=true")
    info "DHCP Proxy mode enabled"
fi

DOCKER_ARGS+=(
    "-v" "$TFTPBOOT_DIR:/tftpboot"
    "-v" "$OUTPUT_DIR:/var/www/html/iso:ro"
    "rocky-pxe-server"
)

# Start container
header "Starting PXE server"
docker "${DOCKER_ARGS[@]}" > /dev/null

# Wait for services to start
sleep 2

# Verify container is running
if ! docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
    error "Container failed to start. Check logs with: docker logs $CONTAINER_NAME"
fi

# Display success message and instructions
echo ""
if [ "$PROXY_DHCP" = true ]; then
    header "PXE Server Started (Proxy Mode)"
else
    header "PXE Server Started"
fi

info "TFTP: ${SERVER_IP}:69 (UDP)"
info "HTTP: http://${SERVER_IP}:${PORT}/iso/"

if [ "$PROXY_DHCP" = true ]; then
    info "DHCP Proxy: Auto-configured"
    echo ""
    success "No DHCP configuration needed!"
    info "Boot target machine via PXE."
else
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Configure DHCP server with:"
    echo -e "     - Next-Server (option 66): $SERVER_IP"
    echo -e "     - Boot Filename (option 67): pxelinux.0"
    echo -e "  2. Boot target machine via PXE"
    echo ""
    info "See README-PXE.md for DHCP configuration examples"
fi

echo ""
echo -e "${CYAN}Management:${NC}"
echo -e "  ${GRAY}Stop:   docker stop $CONTAINER_NAME${NC}"
echo -e "  ${GRAY}Logs:   docker logs -f $CONTAINER_NAME${NC}"
echo -e "  ${GRAY}Status: curl http://localhost:${PORT}/health${NC}"
echo ""
