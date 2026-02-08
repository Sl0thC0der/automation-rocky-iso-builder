# Testing Guide

This document provides comprehensive test plans for validating the Rocky Linux ISO builder and its features.

## Test Status

| Feature | Status | Last Tested | Tester |
|---------|--------|-------------|--------|
| Basic ISO Build | ✅ Validated | - | - |
| USB Boot Installation | ✅ Validated | - | - |
| AMD GPU Detection | ✅ Validated | 2026-02-08 | System 10.1.1.218 (Ryzen 5 7640HS + Radeon 760M) |
| Intel GPU Detection | ❌ Not Tested | - | - |
| NVIDIA GPU Detection | ❌ Not Tested | - | - |
| PXE Boot (Proxy DHCP) | ❌ Not Tested | - | - |
| PXE Boot (Standard DHCP) | ❌ Not Tested | - | - |
| Pre-baked RPMs | ❌ Not Tested | - | - |

---

## 1. ISO Build Testing

### 1.1 Standard Build (No Pre-bake)

**Prerequisites:**
- Rocky Linux DVD ISO (`Rocky-10.1-x86_64-dvd1.iso`)
- Docker installed
- 12GB free disk space

**Test Procedure:**
```powershell
# Windows
.\build.ps1

# Linux/macOS
./scripts/build_iso.sh -i Rocky-10.1-x86_64-dvd1.iso -k ks.cfg -o output/Rocky-ks.iso
```

**Expected Results:**
- ✅ Build completes without errors
- ✅ Output ISO created in `output/Rocky-ks.iso`
- ✅ ISO size approximately 10-11GB
- ✅ Build time: 5-10 minutes (with tmpfs)

**Success Criteria:**
- Exit code 0
- ISO file exists and is bootable
- ISO checksum embedded (implantisomd5 applied)

---

### 1.2 Pre-baked RPMs Build

**Prerequisites:**
- Same as 1.1
- Internet connection (for RPM downloads)

**Test Procedure:**
```powershell
# Windows
.\build.ps1 -Prebake

# Linux/macOS
./scripts/build_iso.sh -i Rocky-10.1-x86_64-dvd1.iso -k ks.cfg -o output/Rocky-ks.iso -p
```

**Expected Results:**
- ✅ RPM download phase completes
- ✅ `createrepo_c` generates repo metadata
- ✅ ISO includes `/prebaked-rpms` directory
- ✅ ISO size approximately 12-13GB (larger due to RPMs)
- ✅ Build time: 15-20 minutes (includes RPM downloads)

**Success Criteria:**
- Exit code 0
- ISO contains `/prebaked-rpms/repodata/` directory
- Package count matches `scripts/pkg-list.conf`

---

## 2. USB Boot Installation Testing

### 2.1 Basic USB Boot Install

**Prerequisites:**
- Built ISO (from section 1)
- USB drive (16GB minimum)
- Test machine with UEFI support

**Test Procedure:**
1. Write ISO to USB:
   ```powershell
   # Windows - Use Rufus in DD mode
   # Linux
   sudo dd if=output/Rocky-ks.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
2. Boot target machine from USB
3. Monitor installation via console or SSH (if `inst.sshd` enabled)

**Expected Results:**
- ✅ System boots to Anaconda installer
- ✅ Kickstart detected and applied automatically
- ✅ Disk partitioning completes (first disk only)
- ✅ Package installation completes
- ✅ System reboots automatically
- ✅ SSH accessible after reboot

**Success Criteria:**
- Installation completes without errors
- System boots to login prompt
- SSH key authentication works
- Docker and Podman both installed
- User `adminlocal` exists with sudo access

---

### 2.2 Boot Media Detection

**Test Cases:**

| Media Type | Expected Behavior | Status |
|------------|-------------------|--------|
| dd-written USB (iso9660) | Detect and skip, install on first non-USB disk | ❌ Not Tested |
| Ventoy USB | Detect VTOYEFI label, skip, install on first non-USB disk | ❌ Not Tested |
| CD/DVD | Not in `list-harddrives`, naturally skipped | ❌ Not Tested |

**Test Procedure:**
1. Boot from USB containing ISO
2. Have a second disk available for installation
3. Check `/tmp/pre-install.log` during install:
   ```bash
   # During install (via SSH with inst.sshd)
   cat /tmp/pre-install.log
   ```

**Expected Results:**
```
Detected installer media (iso9660): /dev/sdb (will NOT wipe)
=== Detected disks: sda nvme0n1 (installing on: sda) ===
```

**Success Criteria:**
- USB boot device is NOT wiped
- Installation target is correct
- No data loss on installer media

---

## 3. GPU Detection and Configuration Testing

### 3.1 AMD APU Testing

**Prerequisites:**
- System with AMD Ryzen CPU + integrated Radeon graphics
- Example: Ryzen 5 7640HS, Ryzen 7 5700G, Ryzen 9 7950X (with iGPU)

**Test Procedure:**
1. Install Rocky via USB or PXE boot
2. After reboot, SSH into system
3. Run verification commands

**Verification Commands:**
```bash
# 1. Check CPU vendor detection
lscpu | grep "Vendor ID"
# Expected: AuthenticAMD

# 2. Check GPU hardware
lspci | grep VGA
# Expected: AMD/ATI ... [Radeon ...]

# 3. Check driver binding
sudo lspci -k -s $(lspci | grep VGA | cut -d' ' -f1)
# Expected: Kernel driver in use: amdgpu

# 4. Check render node
ls -la /dev/dri/
# Expected: card0  renderD128

# 5. Check loaded modules
lsmod | grep amdgpu
# Expected: amdgpu module loaded

# 6. Check kernel messages
sudo dmesg | grep -i amdgpu | tail -20
# Expected: amdgpu initialized successfully

# 7. Check Vulkan support
vulkaninfo --summary 2>/dev/null | head -20
# Expected: Vulkan instance version, AMD driver info

# 8. Verify no simpledrm
sudo dmesg | grep simpledrm
# Expected: "initcall simpledrm_platform_driver_init blacklisted"

# 9. Check kernel parameters
cat /proc/cmdline | grep initcall_blacklist
# Expected: initcall_blacklist=simpledrm_platform_driver_init

# 10. Check module configuration
cat /etc/modules-load.d/amdgpu.conf
# Expected: amdgpu

# 11. Check dracut configuration
cat /etc/dracut.conf.d/gpu-driver.conf
# Expected: add_drivers+=" amdgpu "
```

**Expected Results:**
- ✅ amdgpu driver bound to GPU (not simple-framebuffer)
- ✅ `/dev/dri/renderD128` exists
- ✅ Vulkan support detected
- ✅ VRAM reported correctly in dmesg
- ✅ No error -22 on amdgpu probe

**Success Criteria:**
- Driver: amdgpu
- Render node: Present
- GPU compute: Available for Docker containers

**Test Status:**
- ✅ **PASSED** on Ryzen 5 7640HS + Radeon 760M (2026-02-08)

---

### 3.2 Intel iGPU Testing

**Prerequisites:**
- System with Intel Core CPU + integrated graphics
- Example: Core i5-13600K, Core i7-12700, Core i9-13900K

**Test Procedure:**
1. Install Rocky via USB or PXE boot
2. After reboot, SSH into system
3. Run verification commands

**Verification Commands:**
```bash
# 1. Check CPU vendor detection
lscpu | grep "Vendor ID"
# Expected: GenuineIntel

# 2. Check GPU hardware
lspci | grep VGA
# Expected: Intel Corporation ... Graphics

# 3. Check driver binding
sudo lspci -k -s $(lspci | grep VGA | cut -d' ' -f1)
# Expected: Kernel driver in use: i915

# 4. Check render node
ls -la /dev/dri/
# Expected: card0  renderD128

# 5. Check loaded modules
lsmod | grep i915
# Expected: i915 module loaded

# 6. Check GuC/HuC firmware
sudo dmesg | grep -i "GuC\|HuC"
# Expected: GuC firmware loaded, HuC firmware loaded

# 7. Check module options
cat /etc/modprobe.d/i915.conf
# Expected: options i915 enable_guc=3

# 8. Check VA-API support
vainfo 2>/dev/null
# Expected: VA-API version, Intel driver info

# 9. Check module configuration
cat /etc/modules-load.d/i915.conf
# Expected: i915

# 10. Check dracut configuration
cat /etc/dracut.conf.d/gpu-driver.conf
# Expected: add_drivers+=" i915 "
```

**Expected Results:**
- ✅ i915 driver bound to GPU
- ✅ `/dev/dri/renderD128` exists
- ✅ GuC/HuC firmware loaded (for modern GPUs)
- ✅ VA-API hardware acceleration available
- ✅ intel-media-driver installed

**Success Criteria:**
- Driver: i915
- Render node: Present
- Hardware acceleration: Available

**Test Status:**
- ❌ **NOT TESTED**

---

### 3.3 NVIDIA GPU Testing (Proprietary Driver)

**Prerequisites:**
- System with discrete NVIDIA GPU
- Supported: RTX 50/40/30/20-series, GTX 16/10-series, Quadro, RTX A-series
- Internet connection during install (for RPMFusion repos)

**Test Procedure:**
1. Install Rocky via USB or PXE boot
2. **Wait 2-5 minutes after first boot** (akmod compiles driver)
3. Monitor driver compilation:
   ```bash
   sudo journalctl -fu akmods
   ```
4. Reboot after compilation completes
5. Run verification commands

**Verification Commands:**
```bash
# 1. Check GPU hardware
lspci | grep -i nvidia
# Expected: NVIDIA Corporation ... [GeForce/Quadro/RTX ...]

# 2. Check driver binding
sudo lspci -k -s $(lspci | grep VGA | cut -d' ' -f1)
# Expected: Kernel driver in use: nvidia

# 3. Check NVIDIA driver version
nvidia-smi
# Expected: GPU table, driver version, CUDA version

# 4. Check render node
ls -la /dev/dri/
# Expected: card0  renderD128

# 5. Check loaded modules
lsmod | grep nvidia
# Expected: nvidia, nvidia_modeset, nvidia_drm, nvidia_uvm

# 6. Check nouveau is blacklisted
cat /etc/modprobe.d/blacklist-nouveau.conf
# Expected: blacklist nouveau

# 7. Check RPMFusion repos installed
dnf repolist | grep rpmfusion
# Expected: rpmfusion-free, rpmfusion-nonfree

# 8. Check NVIDIA packages installed
rpm -qa | grep nvidia
# Expected: akmod-nvidia, xorg-x11-drv-nvidia-cuda, etc.

# 9. Check akmod status
sudo akmods --status
# Expected: All modules compiled

# 10. Check CUDA support
nvidia-smi --query-gpu=compute_cap --format=csv
# Expected: CUDA compute capability version

# 11. Check nvidia-persistenced
systemctl status nvidia-persistenced
# Expected: Active (running)

# 12. Check dracut configuration
cat /etc/dracut.conf.d/gpu-driver.conf
# Expected: add_drivers+=" nvidia nvidia-modeset nvidia-drm nvidia-uvm "
```

**Expected Results:**
- ✅ nvidia driver bound to GPU (not nouveau)
- ✅ `/dev/dri/renderD128` exists
- ✅ nvidia-smi shows GPU info
- ✅ CUDA support available
- ✅ akmod compiled successfully
- ✅ nouveau blacklisted

**Success Criteria:**
- Driver: nvidia (proprietary)
- Render node: Present
- CUDA: Available
- nvidia-smi: Working

**Test Status:**
- ❌ **NOT TESTED**

---

### 3.4 Hybrid Graphics Testing (Intel + NVIDIA)

**Prerequisites:**
- Laptop or workstation with Intel iGPU + NVIDIA dGPU
- Example: Intel Core i7 + NVIDIA RTX 3060

**Test Procedure:**
1. Install Rocky via USB or PXE boot
2. Verify both GPUs are configured
3. Test GPU switching/offloading

**Verification Commands:**
```bash
# 1. Check both GPUs detected
lspci | grep -E 'VGA|3D'
# Expected: Intel VGA controller + NVIDIA 3D controller

# 2. Check both drivers loaded
lsmod | grep -E 'i915|nvidia'
# Expected: Both i915 and nvidia modules

# 3. Check render nodes
ls -la /dev/dri/
# Expected: card0, card1, renderD128, renderD129 (two GPUs)

# 4. Test Intel GPU (default)
glxinfo | grep "OpenGL renderer"
# Expected: Intel GPU

# 5. Test NVIDIA GPU (offload)
__NV_PRIME_RENDER_OFFLOAD=1 glxinfo | grep "OpenGL renderer"
# Expected: NVIDIA GPU
```

**Expected Results:**
- ✅ Both Intel (i915) and NVIDIA (nvidia) drivers loaded
- ✅ Two render nodes present
- ✅ Intel GPU used by default (power saving)
- ✅ NVIDIA GPU available for offloading

**Success Criteria:**
- Both GPUs functional
- No driver conflicts
- GPU switching works

**Test Status:**
- ❌ **NOT TESTED**

---

## 4. PXE Boot Testing

### 4.1 PXE Boot - Proxy DHCP Mode

**Prerequisites:**
- Existing DHCP server on network (e.g., router)
- PXE server machine with Docker
- Rocky ISO and kickstart in repo root
- Target machine with PXE boot enabled in BIOS/UEFI

**Test Procedure:**
1. Start PXE server:
   ```powershell
   .\pxe\start_pxe_server.ps1 -ProxyDHCP
   ```
2. Note the PXE server IP address shown in output
3. Boot target machine via PXE (F12 or network boot option)
4. Monitor installation progress

**Verification Points:**
```bash
# On PXE server - check services
docker ps
# Expected: Container "rocky-pxe-server" running

# Check dnsmasq logs
docker logs rocky-pxe-server | grep dnsmasq
# Expected: DHCP proxy offers, TFTP requests

# Check nginx logs
docker logs rocky-pxe-server | grep nginx
# Expected: HTTP requests for vmlinuz, initrd, ISO
```

**Expected Results:**
- ✅ Target machine receives PXE boot menu
- ✅ TFTP transfers boot files (pxelinux.0, vmlinuz, initrd.img)
- ✅ HTTP downloads ISO and kickstart
- ✅ Installation proceeds automatically
- ✅ System reboots and is accessible via SSH

**Success Criteria:**
- PXE boot completes without manual intervention
- Installation identical to USB boot
- Multiple clients can boot simultaneously

**Test Status:**
- ❌ **NOT TESTED**

---

### 4.2 PXE Boot - Standard DHCP Mode

**Prerequisites:**
- Same as 4.1
- Ability to configure DHCP server (option 66/67)

**Test Procedure:**
1. Configure DHCP server to point to PXE server:
   - DHCP Option 66 (TFTP Server): `<PXE_SERVER_IP>`
   - DHCP Option 67 (Boot Filename): `pxelinux.0`
2. Start PXE server:
   ```powershell
   .\pxe\start_pxe_server.ps1
   ```
3. Boot target machine via PXE
4. Monitor installation progress

**Expected Results:**
- ✅ Same as Proxy DHCP mode
- ✅ More predictable network boot (DHCP server directly provides PXE info)

**Success Criteria:**
- Same as Proxy DHCP mode

**Test Status:**
- ❌ **NOT TESTED**

---

### 4.3 PXE Boot - Multiple Concurrent Clients

**Prerequisites:**
- Working PXE server (from 4.1 or 4.2)
- Multiple target machines (2-5 recommended)

**Test Procedure:**
1. Start PXE server
2. Boot all target machines simultaneously
3. Monitor server logs and resource usage

**Verification Points:**
```bash
# Check concurrent TFTP sessions
docker logs rocky-pxe-server | grep "sent.*bytes"

# Check HTTP bandwidth
docker logs rocky-pxe-server | grep "GET /Rocky"

# Monitor server resources
docker stats rocky-pxe-server
```

**Expected Results:**
- ✅ All machines boot successfully
- ✅ No TFTP timeouts
- ✅ HTTP transfers complete (may be slow if many clients)
- ✅ Server remains responsive

**Success Criteria:**
- At least 3 concurrent installations complete
- No client errors or timeouts

**Test Status:**
- ❌ **NOT TESTED**

---

## 5. Integration Testing

### 5.1 PXE Boot + AMD GPU Auto-Config

**Test:** PXE boot a system with AMD APU

**Expected Results:**
- ✅ PXE boot completes
- ✅ amdgpu driver auto-configured
- ✅ `/dev/dri/renderD128` present after reboot

**Test Status:** ❌ NOT TESTED

---

### 5.2 PXE Boot + Intel GPU Auto-Config

**Test:** PXE boot a system with Intel iGPU

**Expected Results:**
- ✅ PXE boot completes
- ✅ i915 driver auto-configured
- ✅ `/dev/dri/renderD128` present after reboot

**Test Status:** ❌ NOT TESTED

---

### 5.3 PXE Boot + NVIDIA GPU Auto-Config

**Test:** PXE boot a system with NVIDIA GPU

**Expected Results:**
- ✅ PXE boot completes
- ✅ RPMFusion repos added
- ✅ akmod-nvidia compiles on first boot
- ✅ nvidia driver working after reboot

**Test Status:** ❌ NOT TESTED

---

### 5.4 Pre-baked RPMs + GPU Drivers

**Test:** Build ISO with pre-baked RPMs including GPU packages

**Verification:**
```bash
# During install (via inst.sshd SSH access)
ls /tmp/prebaked-rpms/
# Expected: mesa-vulkan-drivers, libvdpau, etc.

cat /etc/yum.repos.d/prebaked-local.repo
# Expected: baseurl=file:///tmp/prebaked-rpms

dnf repolist
# Expected: prebaked-local with priority=1
```

**Expected Results:**
- ✅ GPU packages install from local repo (faster)
- ✅ No network download for mesa/vulkan/libva packages
- ✅ GPU detection still works correctly

**Test Status:** ❌ NOT TESTED

---

## 6. Regression Testing

Test that existing features still work after GPU/PXE additions.

### 6.1 Docker + Podman Coexistence

```bash
# Test Docker
docker run --rm hello-world
docker ps
systemctl status docker

# Test Podman
podman run --rm hello-world
podman ps
systemctl status podman.socket

# Verify no conflicts
which docker  # /usr/bin/docker
which podman  # /usr/bin/podman
rpm -qa | grep podman-docker  # Should be empty (not installed)
```

**Expected:** Both Docker and Podman work independently

**Test Status:** ❌ NOT TESTED (after GPU changes)

---

### 6.2 fail2ban with nftables-allports

```bash
# Check fail2ban status
systemctl status fail2ban
sudo fail2ban-client status sshd

# Check configuration
grep banaction /etc/fail2ban/jail.local
# Expected: banaction = nftables-allports

# Check nftables rules
sudo nft list tables
# Expected: No "table ip filter/nat" warnings about iptables-nft

# Test SSH brute force protection (from another machine)
# Attempt 4+ failed logins
for i in {1..5}; do ssh wronguser@<IP>; done

# Verify ban
sudo fail2ban-client status sshd
# Expected: Banned IP list contains test IP
```

**Expected:** fail2ban blocks after 3 failed attempts, uses native nftables

**Test Status:** ✅ VERIFIED (changed to nftables-allports)

---

### 6.3 SSH Hardening

```bash
# Check SSH config
cat /etc/ssh/sshd_config.d/99-hardening.conf
# Expected: PermitRootLogin no, MaxAuthTries 3, etc.

# Test root login blocked
ssh root@<IP>
# Expected: Permission denied

# Test key authentication
ssh -i ~/.ssh/id_ed25519 adminlocal@<IP>
# Expected: Login successful

# Test password authentication (as fallback)
ssh adminlocal@<IP>
# Expected: Prompts for password
```

**Expected:** SSH hardening rules applied, root login blocked

**Test Status:** ❌ NOT TESTED (after GPU changes)

---

### 6.4 Cockpit Web Console

```bash
# Check Cockpit status
systemctl status cockpit.socket

# Access web console
curl -k https://localhost:9090
# Expected: Cockpit login page HTML

# From browser: https://<IP>:9090
# Expected: Cockpit dashboard loads
```

**Expected:** Cockpit accessible on port 9090

**Test Status:** ❌ NOT TESTED (after GPU changes)

---

### 6.5 Automatic Security Updates

```bash
# Check dnf-automatic configuration
cat /etc/dnf/automatic.conf
# Expected: upgrade_type = security, apply_updates = yes

# Check timer status
systemctl status dnf-automatic.timer
# Expected: Active, next run scheduled

# Check for recent runs
journalctl -u dnf-automatic --since "1 week ago"
# Expected: Security updates applied
```

**Expected:** Security updates run automatically

**Test Status:** ❌ NOT TESTED (after GPU changes)

---

## 7. Performance Testing

### 7.1 ISO Build Time

**Test:** Measure build times with different configurations

| Configuration | Expected Time | Actual Time | Status |
|---------------|---------------|-------------|--------|
| Standard (no prebake, tmpfs) | 5-10 min | - | ❌ NOT TESTED |
| Standard (no prebake, no tmpfs) | 10-15 min | - | ❌ NOT TESTED |
| Pre-baked RPMs | 15-20 min | - | ❌ NOT TESTED |

---

### 7.2 Installation Time

**Test:** Measure installation times

| Installation Method | Expected Time | Actual Time | Status |
|---------------------|---------------|-------------|--------|
| USB Boot (standard) | 10-15 min | - | ❌ NOT TESTED |
| USB Boot (pre-baked) | 8-12 min | - | ❌ NOT TESTED |
| PXE Boot (standard) | 15-20 min | - | ❌ NOT TESTED |
| PXE Boot (pre-baked) | 10-15 min | - | ❌ NOT TESTED |

---

### 7.3 GPU Driver Compilation Time (NVIDIA)

**Test:** Measure akmod-nvidia compilation time

| GPU Model | Driver Version | Compile Time | Status |
|-----------|----------------|--------------|--------|
| RTX 4090 | 560.x | - | ❌ NOT TESTED |
| RTX 3060 | 560.x | - | ❌ NOT TESTED |
| GTX 1660 | 560.x | - | ❌ NOT TESTED |

**Expected:** 2-5 minutes depending on CPU performance

---

## 8. Error Handling Testing

### 8.1 Missing ISO File

**Test:** Run build without Rocky ISO

**Expected:** Clear error message, script exits gracefully

**Test Status:** ❌ NOT TESTED

---

### 8.2 Insufficient Disk Space

**Test:** Run build with less than 12GB free space

**Expected:** Docker or script fails with disk space error

**Test Status:** ❌ NOT TESTED

---

### 8.3 Network Failures During Install

**Test:** Disconnect network during installation

**Expected:**
- Pre-baked: Install continues (all packages local)
- Standard: Install fails on package download

**Test Status:** ❌ NOT TESTED

---

### 8.4 NVIDIA Driver Compilation Failure

**Test:** Simulate akmod compilation failure

**Expected:**
- System still boots (nouveau can be used as fallback)
- Clear error in journalctl

**Test Status:** ❌ NOT TESTED

---

### 8.5 PXE TFTP Timeout

**Test:** Slow network or high load on PXE server

**Expected:**
- Retry mechanisms work
- Client eventually boots or shows clear error

**Test Status:** ❌ NOT TESTED

---

## 9. Hardware Compatibility Matrix

### 9.1 Tested Hardware

| Hardware | CPU | GPU | Boot Method | Result | Date | Notes |
|----------|-----|-----|-------------|--------|------|-------|
| System 10.1.1.218 | AMD Ryzen 5 7640HS | Radeon 760M (Phoenix) | USB | ✅ PASS | 2026-02-08 | amdgpu working, render node created |

### 9.2 Planned Testing Hardware

| Hardware | CPU | GPU | Boot Method | Priority |
|----------|-----|-----|-------------|----------|
| Dell OptiPlex | Intel Core i7-12700 | Intel UHD 770 | USB | High |
| HP Z2 | Intel Xeon W-2245 | NVIDIA Quadro RTX 4000 | USB | High |
| Lenovo ThinkPad | Intel Core i5-1135G7 | Intel Iris Xe | USB | Medium |
| Custom Desktop | AMD Ryzen 9 7950X | NVIDIA RTX 4090 | PXE | High |
| Dell PowerEdge | Intel Xeon Gold | No GPU | PXE | Medium |
| Supermicro Server | AMD EPYC 7713 | No GPU | PXE | Low |

---

## 10. Known Issues and Workarounds

| Issue | Severity | Workaround | Status |
|-------|----------|------------|--------|
| simpledrm built-in on Rocky 10 | Medium | Use `initcall_blacklist` kernel parameter | ✅ Fixed |
| NVIDIA akmod compilation takes 2-5 minutes | Low | Expected behavior, wait for completion | Documented |
| Docker loads unmaintained nft_compat modules | Low | Cosmetic warning, no functional impact | Documented |
| fail2ban nftables-multiport uses compat layer | Medium | Changed to nftables-allports | ✅ Fixed |

---

## 11. Test Reporting

### 11.1 Bug Report Template

When reporting issues, include:

```markdown
## Bug Report

**Component:** [ISO Build / USB Boot / PXE Boot / GPU Detection / Other]

**Description:**
[Clear description of the issue]

**Steps to Reproduce:**
1.
2.
3.

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happened]

**Environment:**
- Rocky Linux Version:
- Build Method: [USB / PXE]
- Hardware: [CPU / GPU model]
- Pre-baked RPMs: [Yes / No]

**Logs:**
```
[Paste relevant logs]
```

**Additional Context:**
[Any other information]
```

### 11.2 Test Result Template

When submitting test results:

```markdown
## Test Result: [Test Name]

**Tester:** [Your name]
**Date:** [YYYY-MM-DD]
**Hardware:** [CPU / GPU model]

**Test Procedure:**
[Brief description or reference to test section]

**Result:** [PASS / FAIL / PARTIAL]

**Observations:**
-
-

**Logs/Screenshots:**
[If applicable]

**Notes:**
[Any deviations from expected behavior]
```

---

## 12. Testing Checklist

Use this checklist to track testing progress:

### Essential Tests (Minimum for Release)
- [ ] 1.1 Standard ISO Build
- [ ] 2.1 USB Boot Installation
- [ ] 3.1 AMD GPU Detection (✅ DONE)
- [ ] 3.2 Intel GPU Detection
- [ ] 3.3 NVIDIA GPU Detection
- [ ] 4.1 PXE Boot - Proxy DHCP Mode
- [ ] 6.2 fail2ban with nftables-allports (✅ DONE)

### Additional Tests (Recommended)
- [ ] 1.2 Pre-baked RPMs Build
- [ ] 2.2 Boot Media Detection
- [ ] 3.4 Hybrid Graphics Testing
- [ ] 4.2 PXE Boot - Standard DHCP Mode
- [ ] 4.3 PXE Boot - Multiple Concurrent Clients
- [ ] 5.1-5.4 Integration Testing (all)
- [ ] 6.1 Docker + Podman Coexistence
- [ ] 6.3-6.5 SSH/Cockpit/Updates Regression

### Optional Tests (Nice to Have)
- [ ] 7.1-7.3 Performance Testing
- [ ] 8.1-8.5 Error Handling Testing

---

## 13. Contributing Test Results

To contribute test results:

1. Fork the repository
2. Run tests from this document
3. Update test status tables with results
4. Create a pull request with:
   - Updated TESTING.md
   - Logs (if applicable)
   - Hardware details

Or open an issue at: https://github.com/Sl0thC0der/automation-rocky-iso-builder/issues

---

## Appendix A: Test Environment Setup

### A.1 Physical Test Lab (Recommended)

**Minimum:**
- 1x PXE server machine (Linux/Windows with Docker)
- 1x Target machine with AMD APU
- 1x Target machine with Intel iGPU
- 1x Target machine with NVIDIA GPU
- Gigabit network switch
- USB drive (16GB+)

**Ideal:**
- Same as minimum + multiple target machines for concurrent testing
- Dedicated DHCP server for standard PXE mode testing

### A.2 Virtual Test Lab (Limited)

**Not suitable for:**
- GPU driver testing (no GPU passthrough)
- PXE boot testing (complex network setup)

**Suitable for:**
- ISO build testing
- Basic installation testing (without GPU)
- Kickstart validation

### A.3 Test Automation (Future)

**Potential tools:**
- GitHub Actions for ISO builds
- Ansible for automated test execution
- Selenium/Playwright for Cockpit UI testing
- Custom scripts for hardware validation

---

**Last Updated:** 2026-02-08
**Document Version:** 1.0
