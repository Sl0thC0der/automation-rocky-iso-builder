<#
.SYNOPSIS
    Build a Rocky Linux kickstart ISO with optional pre-baked RPMs.

.DESCRIPTION
    PowerShell wrapper around scripts/build_iso.sh.
    Requires Docker Desktop running and Git Bash installed.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Prebake
    .\build.ps1 -InputISO "Rocky-10.1-x86_64-dvd1.iso" -Kickstart "ks.cfg"
#>
param(
    [string]$InputISO = "Rocky-10.1-x86_64-dvd1.iso",
    [string]$Kickstart = "ks.cfg",
    [string]$OutputISO = "output/Rocky-ks.iso",
    [switch]$Prebake
)

$ErrorActionPreference = "Stop"
$RepoDir = $PSScriptRoot

# Find Git Bash
$GitBash = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $GitBash) {
    Write-Error "Git Bash not found. Install Git for Windows: https://git-scm.com"
    exit 1
}

# Check Docker is running
if (-not (Get-Process "com.docker*" -ErrorAction SilentlyContinue)) {
    Write-Error "Docker Desktop is not running. Start it first."
    exit 1
}

# Validate inputs
if (-not (Test-Path "$RepoDir\$InputISO")) {
    Write-Error "Input ISO not found: $RepoDir\$InputISO"
    exit 1
}
if (-not (Test-Path "$RepoDir\$Kickstart")) {
    Write-Error "Kickstart not found: $RepoDir\$Kickstart"
    exit 1
}

# Remove old output ISO (mkksiso refuses to overwrite)
$OutPath = Join-Path $RepoDir $OutputISO
if (Test-Path $OutPath) {
    Remove-Item $OutPath -Force
    Write-Host "Removed old ISO: $OutputISO" -ForegroundColor Yellow
}

# Build command
$flags = "-i `"$InputISO`" -k `"$Kickstart`" -o `"$OutputISO`""
if ($Prebake) {
    $flags += " -p"
}

$cmd = "cd '$($RepoDir -replace '\\','/')' && ./scripts/build_iso.sh $flags"

$buildStart = Get-Date

Write-Host ""
Write-Host "=== Rocky Kickstart ISO Builder ===" -ForegroundColor Cyan
Write-Host "  Started:   $($buildStart.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "  Input:     $InputISO"
Write-Host "  Kickstart: $Kickstart"
Write-Host "  Output:    $OutputISO"
Write-Host "  Pre-bake:  $Prebake"
Write-Host ""

& $GitBash -lc $cmd

$buildEnd = Get-Date
$elapsed = $buildEnd - $buildStart
$elapsedStr = "{0:mm\:ss}" -f $elapsed
if ($elapsed.TotalHours -ge 1) { $elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed }

if ($LASTEXITCODE -eq 0) {
    $iso = Get-Item $OutPath
    $sizeMB = [math]::Round($iso.Length / 1MB)
    Write-Host ""
    Write-Host "=== Done ===" -ForegroundColor Green
    Write-Host "  ISO: $OutPath ($sizeMB MB)"
    Write-Host "  Finished:  $($buildEnd.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "  Duration:  $elapsedStr"
} else {
    Write-Host ""
    Write-Host "=== FAILED ===" -ForegroundColor Red
    Write-Host "  Finished:  $($buildEnd.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "  Duration:  $elapsedStr"
    Write-Error "Build failed with exit code $LASTEXITCODE"
}
