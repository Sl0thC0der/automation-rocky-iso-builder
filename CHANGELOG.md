# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- PXE boot server container for network installation
- Dual mode: manual DHCP (default) or DHCP proxy (automated)
- PowerShell wrapper `pxe/start_pxe_server.ps1` for Windows
- Bash wrapper `pxe/start_pxe_server.sh` for Linux/macOS
- Automatic boot file extraction from ISO via xorriso
- TFTP (dnsmasq) + HTTP (nginx) in containerized stack
- Auto-detection of host IP for PXE menu configuration
- Comprehensive PXE documentation in `README-PXE.md`

## [1.0.0] - 2026-02-06

### Added

- Rocky kickstart ISO builder with Docker-based build pipeline
- Pre-baked RPM support for faster offline installs
- PowerShell wrapper for Windows builds
- Boot media detection (USB, Ventoy, CD/DVD, PXE)
- Dynamic disk partitioning via %pre script
- DHCP hostname support via NetworkManager
- Build speed optimization with tmpfs (~11 min to ~5 min)

### Fixed

- Media check failure on real hardware (xorriso repack + implantisomd5)
- LVM VG name conflict on reinstall over existing Rocky
- Rocky 10 package name changes (iotop-c, cockpit modules)
- Firewalld cascade removal breaking fail2ban (mask instead of remove)
