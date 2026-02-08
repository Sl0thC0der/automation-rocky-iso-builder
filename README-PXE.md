# PXE Boot Server Guide

This guide explains how to use the PXE boot server to install Rocky Linux over the network, eliminating the need for USB/DVD media.

## Table of Contents

- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [Usage Modes](#usage-modes)
- [DHCP Configuration Examples](#dhcp-configuration-examples)
- [Network Requirements](#network-requirements)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

## Quick Start

### Option 1: Manual DHCP Mode (Recommended)

Simple setup with one-time DHCP configuration:

```powershell
# Windows (PowerShell)
.\pxe\start_pxe_server.ps1
```

```bash
# Linux/macOS (Bash)
./pxe/start_pxe_server.sh
```

Then configure your DHCP server once (see [DHCP Configuration](#dhcp-configuration-examples)).

### Option 2: Proxy DHCP Mode (Automated)

Zero DHCP configuration needed:

```powershell
# Windows (PowerShell)
.\pxe\start_pxe_server.ps1 -ProxyDHCP
```

```bash
# Linux/macOS (Bash)
./pxe/start_pxe_server.sh --proxy-dhcp
```

Boot target machines immediately via PXE.

## How It Works

**PXE (Preboot eXecution Environment)** allows computers to boot from the network instead of local media (USB/DVD/HDD).

### Boot Sequence

1. **Client broadcasts DHCP request** on network
2. **DHCP server responds** with IP address + PXE boot information
3. **Client downloads bootloader** (pxelinux.0) via TFTP
4. **Bootloader displays menu** from PXE server
5. **User selects option** (or auto-boot after 5 seconds)
6. **Client downloads kernel/initrd** via TFTP
7. **Installer boots and downloads ISO** via HTTP
8. **Kickstart runs**, fully unattended installation

### Architecture

```
┌─────────────────────┐
│   PXE Client PC     │
│  (Network Boot)     │
└──────────┬──────────┘
           │
           │ DHCP Request (broadcast)
           ▼
┌─────────────────────┐        ┌─────────────────────┐
│   DHCP Server       │◄───────┤  PXE Server (This)  │
│  (Router/Server)    │        │  - TFTP (dnsmasq)   │
│  Provides:          │        │  - HTTP (nginx)     │
│  - IP Address       │        │  - Boot files       │
│  - Next-Server IP   │        │  - Rocky ISO        │
│  - Boot Filename    │        └─────────────────────┘
└─────────────────────┘
           │
           │ Option 66: 192.168.1.10
           │ Option 67: pxelinux.0
           ▼
┌─────────────────────┐
│   PXE Client PC     │
│  Downloads:         │
│  1. pxelinux.0      │ ◄─── TFTP (:69)
│  2. vmlinuz         │
│  3. initrd.img      │
│  4. Rocky-ks.iso    │ ◄─── HTTP (:80)
└─────────────────────┘
```

## Usage Modes

### Manual DHCP Mode (Default)

**How it works:**
- PXE server runs TFTP + HTTP only
- Your existing DHCP server (router/server) provides PXE boot information via Option 66 and Option 67
- One-time DHCP configuration, works forever

**Pros:**
- Simple and reliable
- No network conflicts
- Works with any DHCP server

**Cons:**
- Requires one-time DHCP configuration

**Use when:**
- You have access to your DHCP server settings (router admin, Windows Server, etc.)
- You want a simple, production-ready setup

### Proxy DHCP Mode (Automated)

**How it works:**
- PXE server runs TFTP + HTTP + DHCP proxy
- DHCP proxy listens for PXE requests and provides boot information automatically
- Your existing DHCP server still provides IP addresses (no conflict)

**Pros:**
- Zero DHCP configuration needed
- Fully automated

**Cons:**
- More complex (requires `--network host` mode)
- Potential conflicts with misconfigured DHCP servers
- Not all networks allow DHCP proxy

**Use when:**
- You cannot access DHCP server settings
- Testing on isolated networks
- Rapid prototyping/development

## DHCP Configuration Examples

### Home Routers (Netgear, TP-Link, ASUS, etc.)

1. Log in to router admin panel (usually `http://192.168.1.1`)
2. Navigate to **DHCP Settings** or **LAN Settings**
3. Look for **Advanced DHCP Options** or **Custom DHCP Options**
4. Add these options:
   - **Option 66** (Next-Server): `192.168.1.10` *(PXE server IP)*
   - **Option 67** (Boot Filename): `pxelinux.0`
5. Save settings and reboot router if needed

**Note:** Not all consumer routers support custom DHCP options. If unavailable, use Proxy DHCP mode.

### ISC DHCP Server (Linux)

Edit `/etc/dhcp/dhcpd.conf`:

```conf
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;

    # PXE boot configuration
    next-server 192.168.1.10;           # PXE server IP
    filename "pxelinux.0";               # Boot file
}
```

Restart DHCP service:

```bash
sudo systemctl restart isc-dhcp-server
```

### Windows Server DHCP

1. Open **DHCP Manager** (`dhcpmgmt.msc`)
2. Expand your DHCP server → **IPv4** → **Scope**
3. Right-click **Scope Options** → **Configure Options**
4. Check **066 Boot Server Host Name**:
   - String value: `192.168.1.10` *(PXE server IP)*
5. Check **067 Bootfile Name**:
   - String value: `pxelinux.0`
6. Click **OK** and restart DHCP service

### dnsmasq (Linux)

If using dnsmasq as your DHCP server, add to `/etc/dnsmasq.conf`:

```conf
# DHCP range
dhcp-range=192.168.1.100,192.168.1.200,24h

# PXE boot
dhcp-boot=pxelinux.0,pxeserver,192.168.1.10
```

Restart dnsmasq:

```bash
sudo systemctl restart dnsmasq
```

## Network Requirements

### Ports

The PXE server requires these ports to be open:

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 69   | UDP      | TFTP    | Boot file transfer (pxelinux.0, vmlinuz, initrd.img) |
| 80   | TCP      | HTTP    | ISO download during installation |
| 67   | UDP      | DHCP    | DHCP proxy (only in `--proxy-dhcp` mode) |
| 68   | UDP      | DHCP    | DHCP proxy (only in `--proxy-dhcp` mode) |

### Firewall (Windows)

If Windows Firewall blocks TFTP/HTTP, allow ports:

```powershell
# Allow TFTP (UDP 69)
New-NetFirewallRule -DisplayName "PXE TFTP" -Direction Inbound -Protocol UDP -LocalPort 69 -Action Allow

# Allow HTTP (TCP 80)
New-NetFirewallRule -DisplayName "PXE HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow

# Allow DHCP Proxy (UDP 67-68) - only needed for --proxy-dhcp mode
New-NetFirewallRule -DisplayName "PXE DHCP Proxy" -Direction Inbound -Protocol UDP -LocalPort 67,68 -Action Allow
```

### Firewall (Linux)

```bash
# firewalld
sudo firewall-cmd --permanent --add-service=tftp
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-port=67-68/udp  # Proxy mode only
sudo firewall-cmd --reload

# ufw
sudo ufw allow 69/udp   # TFTP
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 67:68/udp  # DHCP proxy (proxy mode only)
```

### Network Topology

- **Same subnet required:** PXE server and client machines must be on the same network segment
- **No VLANs/segmentation:** DHCP broadcast must reach both DHCP server and PXE server
- **Router compatibility:** Some routers block DHCP proxy traffic (use manual mode if issues occur)

## Troubleshooting

### Issue: No PXE Boot (Client gets IP but doesn't boot from network)

**Symptoms:**
- Client receives IP address from DHCP
- No PXE boot menu appears
- Client boots from local disk

**Causes & Solutions:**

1. **DHCP not configured with PXE options**
   - Verify Option 66 and 67 are set correctly
   - Check DHCP server logs for PXE requests
   - Test: `tcpdump -i eth0 -n port 67` on PXE server (should see DHCP discover with PXE vendor class)

2. **Client network boot disabled in BIOS**
   - Enable **Network Boot** or **PXE Boot** in BIOS/UEFI
   - Set network boot as first boot device
   - Disable **Secure Boot** (SYSLINUX doesn't support Secure Boot)

3. **Wrong boot mode (UEFI vs BIOS)**
   - This PXE server uses SYSLINUX (BIOS mode)
   - Set client BIOS to **Legacy** or **CSM** mode
   - Future enhancement: add UEFI support via GRUB/iPXE

### Issue: TFTP Timeout

**Symptoms:**
- Client starts PXE boot
- Error: "TFTP timeout" or "PXE-E32: TFTP open timeout"

**Causes & Solutions:**

1. **Firewall blocking UDP 69**
   - Check Windows/Linux firewall (see [Network Requirements](#network-requirements))
   - Test locally: `curl tftp://localhost/pxelinux.0 --output /tmp/test`

2. **Wrong server IP**
   - Verify DHCP Option 66 points to correct PXE server IP
   - Auto-detection may pick wrong NIC (VPN, multiple adapters)
   - Override: `.\pxe\start_pxe_server.ps1 -ServerIP 192.168.1.10`

3. **dnsmasq not running**
   - Check logs: `docker logs rocky-pxe-server`
   - Should see: "dnsmasq-tftp: TFTP root is /tftpboot"
   - Restart container if not visible

### Issue: HTTP 404 (ISO not found)

**Symptoms:**
- PXE boot menu appears
- Client downloads vmlinuz and initrd.img
- Installer fails with "Failed to download ISO" or HTTP 404

**Causes & Solutions:**

1. **ISO bind mount failed**
   - Check container mounts: `docker inspect rocky-pxe-server | grep Mounts -A 10`
   - Should see: `/var/www/html/iso` → `<your-path>/output`
   - Verify ISO exists: `docker exec rocky-pxe-server ls -lh /var/www/html/iso/`

2. **Wrong ISO path in PXE menu**
   - Check menu: `cat pxe/tftpboot/pxelinux.cfg/default`
   - Verify `inst.repo=http://<IP>/iso/` matches server IP
   - Re-run `start_pxe_server.ps1` to regenerate menu

3. **nginx not serving files**
   - Test: `curl http://localhost/iso/` (should show directory listing)
   - Check nginx logs: `docker logs rocky-pxe-server | grep nginx`

### Issue: Secure Boot Error

**Symptoms:**
- Client refuses to boot with "Secure Boot Violation" or similar

**Solution:**
- SYSLINUX (pxelinux.0) is NOT signed for Secure Boot
- **Disable Secure Boot** in client BIOS/UEFI settings
- Future enhancement: use iPXE with Secure Boot signing

### Issue: Auto-boot doesn't work (menu timeout ignored)

**Symptoms:**
- PXE menu appears but doesn't auto-select after 5 seconds

**Cause:**
- Some SYSLINUX versions require explicit `DEFAULT` label

**Solution:**
Already configured correctly in `pxe/config/pxelinux.cfg/default`:
```
DEFAULT rocky-auto
TIMEOUT 50
```

If still not working, press `1` to manually select "Install Rocky Linux (Automated Kickstart)".

## Advanced Topics

### Custom Boot Menu

Edit `pxe/config/pxelinux.cfg/default` to customize the boot menu:

```
DEFAULT rocky-auto
TIMEOUT 50              # Timeout in deciseconds (50 = 5 seconds)
PROMPT 0                # 0 = no prompt, 1 = show prompt

LABEL rocky-auto
  MENU LABEL ^1. Install Rocky Linux (Automated Kickstart)
  KERNEL rocky/vmlinuz
  APPEND initrd=rocky/initrd.img inst.repo=http://PXE_SERVER_IP/iso/ inst.ks=http://PXE_SERVER_IP/iso/ks.cfg inst.cmdline inst.sshd rd.live.check=0

LABEL rocky-manual
  MENU LABEL ^2. Install Rocky Linux (Manual)
  KERNEL rocky/vmlinuz
  APPEND initrd=rocky/initrd.img inst.repo=http://PXE_SERVER_IP/iso/ inst.cmdline inst.sshd rd.live.check=0
```

Restart PXE server after changes:
```powershell
docker restart rocky-pxe-server
```

### Viewing Logs

**Real-time logs:**
```bash
docker logs -f rocky-pxe-server
```

**dnsmasq logs (TFTP/DHCP):**
```bash
docker exec rocky-pxe-server tail -f /var/log/dnsmasq.log
```

**nginx logs (HTTP):**
```bash
docker exec rocky-pxe-server tail -f /var/log/nginx/access.log
```

### Testing TFTP Manually

From another machine on the network:

```bash
# Install tftp client
sudo dnf install tftp  # Rocky/RHEL
sudo apt install tftp  # Debian/Ubuntu

# Download bootloader
tftp 192.168.1.10
> get pxelinux.0
> quit

# Verify file downloaded
ls -lh pxelinux.0  # Should be ~26 KB
```

### Testing HTTP Manually

```bash
# List ISO directory
curl http://192.168.1.10/iso/

# Download ISO (test only, will take time)
curl -I http://192.168.1.10/iso/Rocky-ks.iso

# Health check
curl http://192.168.1.10/health
# Expected: OK
```

### Multi-Boot (Multiple ISOs)

To serve multiple Rocky versions or other distros:

1. **Create separate directories:**
   ```bash
   mkdir -p pxe/tftpboot/rocky10
   mkdir -p pxe/tftpboot/rocky9
   ```

2. **Extract boot files for each:**
   ```bash
   ./pxe/extract_boot_files.sh output/Rocky-10-ks.iso pxe/tftpboot/rocky10
   ./pxe/extract_boot_files.sh output/Rocky-9-ks.iso pxe/tftpboot/rocky9
   ```

3. **Update PXE menu** (`pxe/config/pxelinux.cfg/default`):
   ```
   LABEL rocky10
     MENU LABEL ^1. Rocky Linux 10
     KERNEL rocky10/vmlinuz
     APPEND initrd=rocky10/initrd.img inst.repo=http://PXE_SERVER_IP/iso/Rocky-10-ks.iso ...

   LABEL rocky9
     MENU LABEL ^2. Rocky Linux 9
     KERNEL rocky9/vmlinuz
     APPEND initrd=rocky9/initrd.img inst.repo=http://PXE_SERVER_IP/iso/Rocky-9-ks.iso ...
   ```

4. **Bind mount multiple ISOs:**
   ```powershell
   docker run -d --name rocky-pxe-server --network host \
       -v ./pxe/tftpboot:/tftpboot \
       -v ./output:/var/www/html/iso:ro \
       rocky-pxe-server
   ```

### Stopping the PXE Server

```bash
docker stop rocky-pxe-server
docker rm rocky-pxe-server  # Optional: remove container
```

### Rebuilding After ISO Changes

If you rebuild the ISO (`.\build.ps1`), you don't need to extract boot files again (vmlinuz/initrd.img are unlikely to change). Just restart the PXE server:

```bash
docker restart rocky-pxe-server
```

If boot files DO change (kernel update, different Rocky version):
```bash
# Remove old boot files
rm -f pxe/tftpboot/rocky/vmlinuz pxe/tftpboot/rocky/initrd.img

# Re-run PXE server (will auto-extract)
.\pxe\start_pxe_server.ps1
```

## Summary

**Quick reference:**

| Scenario | Command | DHCP Config Needed? |
|----------|---------|---------------------|
| **Simple setup** | `.\pxe\start_pxe_server.ps1` | Yes (one-time) |
| **Zero config** | `.\pxe\start_pxe_server.ps1 -ProxyDHCP` | No |
| **Custom IP** | `.\pxe\start_pxe_server.ps1 -ServerIP 192.168.1.10` | Yes (one-time) |
| **Stop server** | `docker stop rocky-pxe-server` | N/A |
| **View logs** | `docker logs -f rocky-pxe-server` | N/A |

**Common DHCP options:**
- **Option 66** (Next-Server): PXE server IP address
- **Option 67** (Boot Filename): `pxelinux.0`

**Need help?** Check [Troubleshooting](#troubleshooting) or container logs.
