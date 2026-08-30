## Pop!_OS 24.04 WSL Base 0.1.1

A clean, desktop-free Pop!_OS 24.04 LTS base for WSL2.

### Validated

- systemd: **running**
- user systemd: **running**
- user D-Bus: **OK**
- failed systemd units: **0**
- Windows interop: **OK**
- Pop!_OS repositories: **OK**
- desktop: **not installed**
- `pop-wsl doctor`: **READY**

### Install

```powershell
wsl --install --from-file .\Pop_OS-24.04-WSL-Base-0.1.1-x86_64.wsl
```

Then start `Pop_OS-24.04`, complete the English OOBE, and run:

```bash
pop-wsl doctor
```

### 0.1.1 fixes

- installed `kmod`
- added `/etc/modules`
- masked WSL-incompatible tty1, TPM udev and guest-side binfmt units
- preserved Windows interoperability
- verified zero failed units after a WSL cold boot

### Integrity

Download `SHA256SUMS` and verify the release files before installation.

> This is a community WSL build and is not an official System76 WSL image.
