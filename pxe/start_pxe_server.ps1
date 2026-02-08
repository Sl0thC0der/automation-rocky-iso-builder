#!/usr/bin/env pwsh
# Rocky PXE Boot Server Launcher
# Starts a containerized TFTP + HTTP server for network installation

param(
    [string]$ISO = "output\Rocky-ks.iso",
    [int]$Port = 80,
    [switch]$ProxyDHCP,
    [string]$ContainerName = "rocky-pxe-server",
    [string]$ServerIP = ""  # Auto-detect if empty
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Header { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Info { param($msg) Write-Host "  $msg" -ForegroundColor Gray }
function Write-Success { param($msg) Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "! $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "✗ $msg" -ForegroundColor Red }

Write-Header "Rocky PXE Server"
Write-Info "ISO: $ISO"

# Validate prerequisites
Write-Info "Checking prerequisites..."

# Check Docker
try {
    docker version | Out-Null
    Write-Success "Docker is running"
} catch {
    Write-Error "Docker is not running. Please start Docker Desktop."
    exit 1
}

# Check Git Bash (needed for extract script)
$gitBashPaths = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\bin\bash.exe"
)
$bashPath = $gitBashPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $bashPath) {
    Write-Error "Git Bash not found. Please install Git for Windows."
    exit 1
}
Write-Success "Git Bash found at $bashPath"

# Validate ISO exists
$isoPath = Resolve-Path $ISO -ErrorAction SilentlyContinue
if (-not $isoPath) {
    Write-Error "ISO not found at $ISO"
    Write-Info "Build the ISO first with: .\build.ps1"
    exit 1
}
Write-Success "ISO found"

# Build PXE server image if not exists
$imageExists = docker images rocky-pxe-server -q
if (-not $imageExists) {
    Write-Header "Building PXE server image"
    $env:DOCKER_BUILDKIT = "1"
    docker build -t rocky-pxe-server -f pxe\Dockerfile.pxe pxe\
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build PXE server image"
        exit 1
    }
    Write-Success "Image built"
} else {
    Write-Success "PXE server image exists"
}

# Extract boot files if not present
$vmlinuzPath = "pxe\tftpboot\rocky\vmlinuz"
$initrdPath = "pxe\tftpboot\rocky\initrd.img"

if (-not (Test-Path $vmlinuzPath) -or -not (Test-Path $initrdPath)) {
    Write-Header "Extracting boot files from ISO"

    # Convert paths to Unix-style for Git Bash
    $isoUnix = $isoPath.Path -replace '\\', '/' -replace '^([A-Z]):', '/$1'
    $outputUnix = "pxe/tftpboot/rocky"

    & $bashPath -c "cd '$PWD' && ./pxe/extract_boot_files.sh '$ISO' '$outputUnix'"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to extract boot files"
        exit 1
    }
    Write-Success "Boot files extracted"
} else {
    Write-Success "Boot files already extracted"
}

# Auto-detect host IP if not provided
if (-not $ServerIP) {
    Write-Info "Auto-detecting host IP..."

    # Get all IPv4 addresses from active network adapters
    $adapters = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -ne "127.0.0.1" } |
        Sort-Object -Property {
            # Prefer DHCP addresses over static
            if ((Get-NetIPConfiguration -InterfaceAlias $_.InterfaceAlias).IPv4Address.PrefixOrigin -eq "Dhcp") { 0 } else { 1 }
        }

    if ($adapters) {
        $ServerIP = $adapters[0].IPAddress
        Write-Success "Detected IP: $ServerIP"
    } else {
        Write-Warning "Could not auto-detect IP, using 127.0.0.1"
        $ServerIP = "127.0.0.1"
    }
}

# Update PXE boot menu with server IP
Write-Info "Configuring PXE boot menu..."
$menuTemplate = Get-Content "pxe\config\pxelinux.cfg\default" -Raw
$menuConfigured = $menuTemplate -replace 'PXE_SERVER_IP', $ServerIP
Set-Content "pxe\tftpboot\pxelinux.cfg\default" -Value $menuConfigured
Write-Success "Boot menu configured with IP $ServerIP"

# Stop existing container if running
$existingContainer = docker ps -a -q -f name=$ContainerName
if ($existingContainer) {
    Write-Info "Stopping existing container..."
    docker stop $ContainerName 2>&1 | Out-Null
    docker rm $ContainerName 2>&1 | Out-Null
}

# Prepare Docker run arguments
$outputDir = (Resolve-Path "output").Path
$tftpbootDir = (Resolve-Path "pxe\tftpboot").Path

$dockerArgs = @(
    "run", "-d",
    "--name", $ContainerName,
    "--network", "host"
)

# Add DHCP proxy mode if requested
if ($ProxyDHCP) {
    $dockerArgs += "-e", "PROXY_DHCP=true"
    Write-Info "DHCP Proxy mode enabled"
}

$dockerArgs += @(
    "-v", "${tftpbootDir}:/tftpboot",
    "-v", "${outputDir}:/var/www/html/iso:ro",
    "rocky-pxe-server"
)

# Start container
Write-Header "Starting PXE server"
& docker @dockerArgs | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to start PXE server container"
    exit 1
}

# Wait for services to start
Start-Sleep -Seconds 2

# Verify container is running
$running = docker ps -q -f name=$ContainerName
if (-not $running) {
    Write-Error "Container failed to start. Check logs with: docker logs $ContainerName"
    exit 1
}

# Display success message and instructions
Write-Host ""
if ($ProxyDHCP) {
    Write-Header "PXE Server Started (Proxy Mode)"
} else {
    Write-Header "PXE Server Started"
}

Write-Info "TFTP: ${ServerIP}:69 (UDP)"
Write-Info "HTTP: http://${ServerIP}:${Port}/iso/"

if ($ProxyDHCP) {
    Write-Info "DHCP Proxy: Auto-configured"
    Write-Host ""
    Write-Success "No DHCP configuration needed!"
    Write-Info "Boot target machine via PXE."
} else {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Configure DHCP server with:" -ForegroundColor White
    Write-Host "     - Next-Server (option 66): $ServerIP" -ForegroundColor White
    Write-Host "     - Boot Filename (option 67): pxelinux.0" -ForegroundColor White
    Write-Host "  2. Boot target machine via PXE" -ForegroundColor White
    Write-Host ""
    Write-Info "See README-PXE.md for DHCP configuration examples"
}

Write-Host ""
Write-Host "Management:" -ForegroundColor Cyan
Write-Host "  Stop:   docker stop $ContainerName" -ForegroundColor Gray
Write-Host "  Logs:   docker logs -f $ContainerName" -ForegroundColor Gray
Write-Host "  Status: Invoke-WebRequest http://localhost:${Port}/health" -ForegroundColor Gray
Write-Host ""
