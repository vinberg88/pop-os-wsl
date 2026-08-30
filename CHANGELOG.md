# Changelog

## 0.1.1 — WSL cold-boot stable

### Fixed

- Installed `kmod` so `kmod-static-nodes.service` can execute successfully.
- Added `/etc/modules` for conventional kmod/systemd compatibility.
- Masked `getty@tty1.service`, which is not meaningful for a normal WSL login session.
- Masked `tpm-udev.path` and `tpm-udev.service` for the WSL environment.
- Masked `systemd-binfmt.service`; WSL owns `binfmt_misc` and exposes its rule interface read-only to the guest.
- Preserved Windows interoperability while disabling the conflicting guest-side binfmt setup.
- Added builder regression checks for the validated cold-boot fixes.

### Validated

A fresh Pop!_OS 24.04 WSL Base 0.1.1 installation was cold-boot tested with:

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

## 0.1.0 — Initial base

### Added

- Initial Pop!_OS 24.04 LTS WSL base derived from the OCI rootfs.
- Modern `.wsl` package output.
- English first-run OOBE.
- UID/GID 1000 user creation.
- systemd support.
- Windows interoperability and WSL DNS configuration.
- Pop!_OS repository preservation.
- `pop-wsl doctor`, `pop-wsl info`, and `pop-wsl version`.
- Desktop-free base policy.

### Initial cold-boot findings

The first release exposed WSL-specific failures involving TPM udev units, tty1, `systemd-binfmt`, and a missing `kmod` executable. These were resolved and incorporated into 0.1.1.
