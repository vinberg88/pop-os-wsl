# Pop!_OS 24.04 LTS WSL Base

<img width="900" height="520" alt="PoPOS" src="https://github.com/user-attachments/assets/745add75-2429-460c-8282-b3a8ca0cd0e1" />


Look for more stuff here for WSL - https://github.com/vinberg88

A minimal, desktop-free **Pop!_OS 24.04 LTS** distribution for **Windows Subsystem for Linux 2 (WSL2)**.

This project is intended to provide a clean Pop!_OS base for terminal, development, DevOps and user-selected desktop workloads. No desktop environment, display manager, X11 server configuration, Wayland compositor, or third-party display-server configuration is preinstalled.

## Release

**Current release:** `0.1.1`  
**Base OS:** Pop!_OS 24.04 LTS (`noble`)  
**Architecture:** x86_64 / amd64  
**Source OCI image:** `ghcr.io/aldpuzz/pop_os:latest`  
**Default locale:** `en_US.UTF-8`  
**systemd:** enabled

The source image digest used for each build is recorded in `MANIFEST.txt` so a release can be traced back to the exact OCI image that was exported.

## Features

- Pop!_OS 24.04 LTS userspace
- WSL2 support
- systemd as PID 1
- English first-run OOBE
- normal UNIX user created with UID/GID 1000
- sudo configured for the OOBE-created user
- Windows interoperability enabled
- WSLg-compatible base environment
- Pop!_OS repositories preserved
- DNS managed by WSL
- `en_US.UTF-8` default locale
- no desktop environment
- no display manager
- no X410-specific configuration
- built-in `pop-wsl` diagnostics

## Install

### Option 1 — File Explorer

Double-click:

```text
Pop_OS-24.04-WSL-Base-0.1.1-x86_64.wsl
```

### Option 2 — PowerShell

```powershell
wsl --install --from-file .\Pop_OS-24.04-WSL-Base-0.1.1-x86_64.wsl
```

Then start the distribution:

```powershell
wsl -d Pop_OS-24.04
```

On first launch, the English OOBE asks for a username and password. The account is created with UID/GID 1000 and added to the `sudo` group.

## Validate the installation

Inside Pop!_OS WSL:

```bash
pop-wsl doctor
```

A healthy clean installation should report:

```text
systemd:               running
User systemd:          running
User D-Bus:            OK
Failed units:          0
Windows interop:       OK
Pop!_OS repositories:  OK
Desktop:               not installed
Status:                READY
```

Additional commands:

```bash
pop-wsl info
pop-wsl version
```

## Update

Use the normal Pop!_OS/Ubuntu package workflow:

```bash
sudo apt update
sudo apt full-upgrade
```

## Desktop environments

A desktop is deliberately **not** included. Install whatever desktop stack you want after the base system is running.

This keeps the distribution small, generic and suitable for normal WSL use instead of tying it to a particular desktop, X server or compositor.

## 0.1.1 WSL cold-boot fixes

Release 0.1.1 contains the fixes validated on a clean WSL2 cold boot:

- installs `kmod`
- creates `/etc/modules`
- masks `getty@tty1.service`
- masks `tpm-udev.path`
- masks `tpm-udev.service`
- masks `systemd-binfmt.service` because WSL owns the read-only `binfmt_misc` interface
- intentionally keeps `kmod-static-nodes.service` available

Windows interoperability remains enabled.

## Verify downloads

From Linux/WSL:

```bash
sha256sum -c SHA256SUMS
```

From PowerShell, for the `.wsl` file:

```powershell
Get-FileHash .\Pop_OS-24.04-WSL-Base-0.1.1-x86_64.wsl -Algorithm SHA256
```

Compare the result with `SHA256SUMS` from the same release.

## Build from source

Requirements:

- Linux or WSL environment
- Docker available to the current user
- network access to GHCR and the Pop!_OS repositories

Build:

```bash
chmod +x build-pop-os-wsl-0.1.1.sh
./build-pop-os-wsl-0.1.1.sh
```

Rebuild an existing release directory:

```bash
./build-pop-os-wsl-0.1.1.sh --force
```

Default output:

```text
~/pop-os-wsl-0.1.1/
```

The builder produces:

```text
Pop_OS-24.04-WSL-Base-0.1.1-x86_64.wsl
Pop_OS-24.04-WSL-Base-0.1.1-x86_64-rootfs.tar.gz
README.txt
MANIFEST.txt
SHA256SUMS
```

The `.wsl` and `-rootfs.tar.gz` files are intentionally byte-identical gzip-compressed tar archives. For a public GitHub release, uploading the `.wsl` file is normally sufficient; the rootfs archive is optional and duplicates the same bytes.

## Uninstall

> **Warning:** This permanently deletes the selected WSL distribution and all data stored inside it.

```powershell
wsl --unregister Pop_OS-24.04
```

## Source and project status

This is a **community WSL build**. The OCI rootfs source used by this builder is `ghcr.io/aldpuzz/pop_os:latest`; it is not presented as an official System76 WSL image. The builder validates that the source identifies itself as Pop!_OS 24.04 / Noble and verifies the expected Pop!_OS repository entries before packaging.

Pop!_OS and System76 names and marks belong to their respective owners. This project is not affiliated with or endorsed by System76.

How to install GNOME dekstop - WSL - https://github.com/vinberg88/pop-os-wsl/blob/main/POP-OS-24.04-GNOME.txt

<img width="1920" height="1080" alt="POP-OS-24 04-GNOME" src="https://github.com/user-attachments/assets/651027b2-8702-4027-8c59-7cc88d0aae0c" />

How to install UKUI desktop - WSL - https://github.com/vinberg88/pop-os-wsl/blob/main/POP-OS-24.04-UKUI.txt

<img width="1920" height="1080" alt="POP-OS-UKUI" src="https://github.com/user-attachments/assets/dfe127da-e898-4b1e-8643-dc75de00f1a6" />

How to install BUDGIE desktop - WSL - https://github.com/vinberg88/pop-os-wsl/blob/main/POP-OS-BUDGIE.txt

<img width="1920" height="1080" alt="POP-OS-BUDGIE" src="https://github.com/user-attachments/assets/955a145f-0338-45ff-b743-e68fa27aa160" />


Regards,
Mattias Vinberg - Stockholm - Sweden
