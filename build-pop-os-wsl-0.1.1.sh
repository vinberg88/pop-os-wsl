#!/usr/bin/env bash
#
# Pop!_OS 24.04 WSL Base Builder 0.1.1
# Source rootfs: ghcr.io/aldpuzz/pop_os:latest
#
# Builds a desktop-free Pop!_OS 24.04 LTS WSL distribution using the modern
# .wsl tar-based distribution format (WSL 2.4.4+).
#
# The builder intentionally keeps the base generic:
#   - English OOBE
#   - en_US.UTF-8
#   - Etc/UTC
#   - systemd enabled
#   - no desktop environment / display manager
#   - Pop!_OS repositories preserved
#
# 0.1.1 WSL cold-boot fixes validated on Pop!_OS 24.04:
#   - install kmod and provide /etc/modules
#   - mask getty@tty1.service
#   - mask tpm-udev.path and tpm-udev.service
#   - mask systemd-binfmt.service (WSL owns read-only binfmt_misc)
#   - keep kmod-static-nodes.service enabled
#
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

BUILDER_VERSION="0.1.1"
DISTRO_VERSION="24.04"
DISTRO_PRETTY="Pop!_OS 24.04 LTS"
DEFAULT_DISTRO_NAME="Pop_OS-24.04"
DEFAULT_IMAGE="ghcr.io/aldpuzz/pop_os:latest"
IMAGE="${POP_OS_IMAGE:-$DEFAULT_IMAGE}"
ARCH_NAME="x86_64"
FORCE=0
NO_PULL=0
KEEP_CONTAINER=0
CUSTOM_OUTPUT=""

usage() {
  cat <<'EOF'
Pop!_OS 24.04 WSL Base Builder 0.1.1

Usage:
  ./build-pop-os-wsl-0.1.1.sh [options]

Options:
  --force           Replace an existing release directory.
  --no-pull         Use the locally cached Docker image without pulling.
  --keep-container  Keep the temporary Docker container after the build.
  --output DIR      Write the release to DIR instead of the default path.
  --image IMAGE     Use a different OCI/Docker image.
  -h, --help        Show this help.

Environment:
  POP_OS_IMAGE      Same as --image.

Default output:
  ~/pop-os-wsl-0.1.1/
EOF
}

log()  { printf '[POP WSL] %s\n' "$*"; }
ok()   { printf '[OK]      %s\n' "$*"; }
warn() { printf '[WARN]    %s\n' "$*" >&2; }
die()  { printf '[ERROR]   %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --force) FORCE=1 ;;
    --no-pull) NO_PULL=1 ;;
    --keep-container) KEEP_CONTAINER=1 ;;
    --output)
      shift
      (($#)) || die "--output requires a directory."
      CUSTOM_OUTPUT="$1"
      ;;
    --image)
      shift
      (($#)) || die "--image requires an image reference."
      IMAGE="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

for cmd in docker gzip tar sha256sum awk sed grep sort date mktemp stat cp getent id; do
  need_cmd "$cmd"
done

# Resolve the real invoking user's home even when the builder is run via sudo.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  INVOKING_USER="$SUDO_USER"
  INVOKING_HOME="$(getent passwd "$SUDO_USER" 2>/dev/null | awk -F: '{print $6}')"
  [[ -n "$INVOKING_HOME" ]] || INVOKING_HOME="/home/$SUDO_USER"
else
  INVOKING_USER="${USER:-$(id -un)}"
  INVOKING_HOME="${HOME:-$(getent passwd "$(id -un)" | awk -F: '{print $6}')}"
fi

if [[ -n "$CUSTOM_OUTPUT" ]]; then
  RELEASE_DIR="$CUSTOM_OUTPUT"
else
  RELEASE_DIR="${INVOKING_HOME}/pop-os-wsl-${BUILDER_VERSION}"
fi

ARTIFACT_BASE="Pop_OS-${DISTRO_VERSION}-WSL-Base-${BUILDER_VERSION}-${ARCH_NAME}"
WSL_FILE="${RELEASE_DIR}/${ARTIFACT_BASE}.wsl"
ROOTFS_FILE="${RELEASE_DIR}/${ARTIFACT_BASE}-rootfs.tar.gz"
README_FILE="${RELEASE_DIR}/README.txt"
MANIFEST_FILE="${RELEASE_DIR}/MANIFEST.txt"
SHA_FILE="${RELEASE_DIR}/SHA256SUMS"

if [[ -e "$RELEASE_DIR" ]]; then
  if (( FORCE )); then
    log "Removing existing release directory: $RELEASE_DIR"
    rm -rf -- "$RELEASE_DIR"
  else
    die "Release directory already exists: $RELEASE_DIR (use --force to replace it)"
  fi
fi
mkdir -p -- "$RELEASE_DIR"

TMP_DIR="$(mktemp -d -t pop-os-wsl-0.1.1.XXXXXX)"
CONTAINER_NAME="pop-os-wsl-build-${BUILDER_VERSION//./-}-$$"
CONTAINER_CREATED=0

cleanup() {
  local rc=$?
  if (( CONTAINER_CREATED )) && (( ! KEEP_CONTAINER )); then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TMP_DIR"
  if (( rc != 0 )); then
    warn "Build failed with exit code $rc."
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

printf '\n'
printf '============================================================\n'
printf '  Pop!_OS 24.04 WSL Base Builder %s\n' "$BUILDER_VERSION"
printf '============================================================\n'
printf 'Source image:  %s\n' "$IMAGE"
printf 'Output:        %s\n' "$RELEASE_DIR"
printf 'Desktop:       none\n'
printf 'Locale:        en_US.UTF-8\n'
printf 'Timezone:      Etc/UTC\n'
printf 'systemd:       enabled\n'
printf '\n'

if ! docker info >/dev/null 2>&1; then
  die "Docker is not available to this user. Start Docker or fix Docker permissions first."
fi

if (( ! NO_PULL )); then
  log "Pulling source image..."
  docker pull "$IMAGE"
else
  log "Using locally cached source image (--no-pull)."
  docker image inspect "$IMAGE" >/dev/null 2>&1 || die "Image is not available locally: $IMAGE"
fi

IMAGE_ARCH="$(docker image inspect "$IMAGE" --format '{{.Architecture}}')"
[[ "$IMAGE_ARCH" == "amd64" ]] || die "This 0.1.1 builder supports amd64 only; source image reports: $IMAGE_ARCH"

IMAGE_ID="$(docker image inspect "$IMAGE" --format '{{.Id}}')"
IMAGE_DIGEST="$(docker image inspect "$IMAGE" --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}unavailable{{end}}')"
IMAGE_VOLUMES="$(docker image inspect "$IMAGE" --format '{{json .Config.Volumes}}')"
if [[ "$IMAGE_VOLUMES" != "null" && "$IMAGE_VOLUMES" != "<nil>" && "$IMAGE_VOLUMES" != "{}" ]]; then
  die "Source image declares Docker volumes ($IMAGE_VOLUMES). Refusing to export an incomplete rootfs."
fi
ok "Source image architecture: amd64"
ok "Source image digest: $IMAGE_DIGEST"

# Validate that the source is really the expected Pop!_OS 24.04 rootfs.
OS_PROBE="$(docker run --rm --entrypoint /bin/sh "$IMAGE" -c '. /etc/os-release; printf "%s|%s|%s|%s" "$ID" "$VERSION_ID" "$VERSION_CODENAME" "$PRETTY_NAME"')"
IFS='|' read -r OS_ID OS_VERSION OS_CODENAME OS_PRETTY <<< "$OS_PROBE"
[[ "$OS_ID" == "pop" ]] || die "Unexpected source ID: $OS_ID (expected: pop)"
[[ "$OS_VERSION" == "24.04" ]] || die "Unexpected source VERSION_ID: $OS_VERSION (expected: 24.04)"
[[ "$OS_CODENAME" == "noble" ]] || die "Unexpected source codename: $OS_CODENAME (expected: noble)"
ok "Verified source OS: $OS_PRETTY"

log "Creating temporary build container: $CONTAINER_NAME"
docker create \
  --name "$CONTAINER_NAME" \
  --user 0 \
  --entrypoint /bin/sh \
  "$IMAGE" \
  -c 'trap "exit 0" TERM INT; while :; do sleep 3600 & wait $!; done' \
  >/dev/null
CONTAINER_CREATED=1
docker start "$CONTAINER_NAME" >/dev/null

log "Installing WSL base packages..."
docker exec \
  -e DEBIAN_FRONTEND=noninteractive \
  -e NEEDRESTART_MODE=a \
  -e APT_LISTCHANGES_FRONTEND=none \
  -e TZ=Etc/UTC \
  "$CONTAINER_NAME" \
  /bin/bash -euxo pipefail -c '
    apt-get update
    apt-get full-upgrade -y

    # The Pop!_OS container rootfs does not ship /etc/modules.  The kmod
    # package expects the file to exist on a conventional system, and WSL
    # cold boot uses kmod-static-nodes.service.
    touch /etc/modules
    chmod 0644 /etc/modules

    apt-get install -y --no-install-recommends \
      adduser \
      bash-completion \
      ca-certificates \
      curl \
      dbus \
      dbus-user-session \
      dnsutils \
      file \
      git \
      gnupg \
      iproute2 \
      iputils-ping \
      kmod \
      less \
      libnss-systemd \
      libpam-systemd \
      locales \
      lsof \
      nano \
      openssh-client \
      passwd \
      pciutils \
      procps \
      rsync \
      sudo \
      systemd \
      systemd-sysv \
      tzdata \
      unzip \
      usbutils \
      util-linux \
      vim-tiny \
      wget \
      xz-utils \
      zip

    # English, distribution-neutral defaults.
    sed -i -E "s/^[#[:space:]]*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8
    ln -snf /usr/share/zoneinfo/Etc/UTC /etc/localtime
    printf "Etc/UTC\n" > /etc/timezone

    # The upstream Docker image ships with the standard Ubuntu seed account
    # (ubuntu:1000:1000). A reusable WSL distribution must leave UID/GID 1000
    # free so the first-run OOBE can create the user chosen by the installer.
    if getent passwd 1000 >/dev/null; then
      seed_user="$(getent passwd 1000 | cut -d: -f1)"
      if [[ "$seed_user" == "ubuntu" ]]; then
        echo "Removing upstream Docker seed user: ubuntu (UID 1000)"
        userdel -r ubuntu 2>/dev/null || userdel ubuntu
        rm -rf /home/ubuntu
        rm -f /etc/sudoers.d/ubuntu
      else
        echo "UID 1000 is occupied by an unexpected account:" >&2
        getent passwd 1000 >&2
        exit 20
      fi
    fi

    if getent group 1000 >/dev/null; then
      seed_group="$(getent group 1000 | cut -d: -f1)"
      if [[ "$seed_group" == "ubuntu" ]]; then
        echo "Removing upstream Docker seed group: ubuntu (GID 1000)"
        groupdel ubuntu
      else
        echo "GID 1000 is occupied by an unexpected group:" >&2
        getent group 1000 >&2
        exit 21
      fi
    fi

    if getent passwd 1000 >/dev/null || getent group 1000 >/dev/null; then
      echo "Failed to release UID/GID 1000 for the WSL OOBE account." >&2
      exit 23
    fi

    # The base release is intentionally desktop-free.
    for pkg in gdm3 sddm lightdm cosmic-session gnome-shell plasma-workspace ukui-session-manager xfce4-session; do
      if dpkg-query -W -f="\${Status}" "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        echo "Desktop/display-manager package unexpectedly installed: $pkg" >&2
        exit 22
      fi
    done

    # Verify the Pop!_OS repositories before packaging.
    grep -Rqs "apt.pop-os.org/release" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
    grep -Rqs "apt.pop-os.org/ubuntu" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
    grep -Rqs "apt.pop-os.org/proprietary" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
  '
ok "Required packages installed and Pop!_OS repositories verified."

# Files copied into the container are intentionally created outside the rootfs first.
cat > "${TMP_DIR}/wsl.conf" <<'EOF'
[boot]
systemd=true

[network]
generateResolvConf=true
generateHosts=true

[interop]
enabled=true
appendWindowsPath=true
EOF

cat > "${TMP_DIR}/wsl-distribution.conf" <<EOF
[oobe]
command=/usr/lib/wsl/oobe.sh
defaultUid=1000
defaultName=${DEFAULT_DISTRO_NAME}
EOF

cat > "${TMP_DIR}/oobe.sh" <<'OOBE'
#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

printf '\n'
printf '============================================\n'
printf '       Pop!_OS 24.04 WSL Setup\n'
printf '============================================\n'
printf '\n'
printf 'Welcome to Pop!_OS 24.04 LTS for WSL.\n'
printf '\n'
printf 'Create your default UNIX user account.\n'
printf 'The account will use UID 1000 and will be added to sudo.\n'
printf '\n'

if [[ "$(id -u)" -ne 0 ]]; then
  echo "OOBE must run as root." >&2
  exit 1
fi

if getent passwd 1000 >/dev/null 2>&1; then
  existing_user="$(getent passwd 1000 | cut -d: -f1)"
  printf 'UID 1000 is already assigned to %s.\n' "$existing_user"
  printf 'Using that account as the WSL default user.\n'
  username="$existing_user"
else
  while :; do
    read -r -p 'Username: ' username
    username="${username,,}"

    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
      echo "Use lowercase letters, digits, underscore or hyphen; start with a letter or underscore."
      continue
    fi
    if ((${#username} > 32)); then
      echo "Username must be 32 characters or fewer."
      continue
    fi
    if [[ "$username" == "root" ]]; then
      echo "The username 'root' is reserved."
      continue
    fi
    if getent passwd "$username" >/dev/null 2>&1; then
      echo "That username already exists. Choose another one."
      continue
    fi
    break
  done

  if getent group 1000 >/dev/null 2>&1; then
    echo "GID 1000 is already in use; cannot create the default WSL account safely." >&2
    exit 1
  fi
  groupadd --gid 1000 "$username"
  useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash "$username"

  groups=()
  for group in sudo adm audio video plugdev cdrom dialout users; do
    if getent group "$group" >/dev/null 2>&1; then
      groups+=("$group")
    fi
  done
  if ((${#groups[@]})); then
    joined="$(IFS=,; echo "${groups[*]}")"
    usermod -aG "$joined" "$username"
  fi

  printf '\nSet the password for %s.\n' "$username"
  until passwd "$username"; do
    echo "Password setup failed. Please try again."
  done
fi

# Add the selected user as the default for tools/WSL versions that read wsl.conf.
if ! grep -q '^\[user\]$' /etc/wsl.conf 2>/dev/null; then
  cat >> /etc/wsl.conf <<EOF

[user]
default=$username
EOF
else
  # Replace an existing default= line inside a simple [user] section if present.
  awk -v u="$username" '
    BEGIN { in_user=0; wrote=0 }
    /^\[/ {
      if (in_user && !wrote) { print "default=" u; wrote=1 }
      in_user = ($0 == "[user]")
      print
      next
    }
    in_user && /^default=/ { print "default=" u; wrote=1; next }
    { print }
    END { if (in_user && !wrote) print "default=" u }
  ' /etc/wsl.conf > /etc/wsl.conf.tmp
  mv /etc/wsl.conf.tmp /etc/wsl.conf
  chmod 0644 /etc/wsl.conf
fi

install -d -m 0700 -o "$username" -g "$username" "/home/$username/.config"
chown -R "$username:$username" "/home/$username"

printf '\n'
printf 'Setup complete.\n'
printf '\n'
printf 'Default user: %s (UID 1000)\n' "$username"
printf 'Locale:       en_US.UTF-8\n'
printf 'Timezone:     Etc/UTC\n'
printf 'systemd:      enabled\n'
printf '\n'
printf 'Run "pop-wsl doctor" after the distribution starts.\n'
printf '\n'
OOBE

cat > "${TMP_DIR}/pop-wsl" <<'POPWSL'
#!/usr/bin/env bash
set -u

VERSION="0.1.1"
DISTRO="Pop!_OS 24.04 WSL Base"

value_or_unknown() {
  local v="${1:-}"
  [[ -n "$v" ]] && printf '%s' "$v" || printf 'unknown'
}

is_wsl() {
  grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null || \
    grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null
}

repo_ok() {
  grep -Rqs 'apt.pop-os.org/release' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null && \
  grep -Rqs 'apt.pop-os.org/ubuntu' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null && \
  grep -Rqs 'apt.pop-os.org/proprietary' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
}

desktop_state() {
  if compgen -G '/usr/share/xsessions/*.desktop' >/dev/null 2>&1 || \
     compgen -G '/usr/share/wayland-sessions/*.desktop' >/dev/null 2>&1; then
    printf 'installed'
  else
    printf 'not installed'
  fi
}

doctor() {
  local kernel wsl wslg interop pid1 sys_state user_sys user_bus failed user uid locale timezone dns rootfs desktop repos status

  kernel="$(uname -r 2>/dev/null || true)"
  if is_wsl; then wsl="yes"; else wsl="no"; fi
  if [[ -d /mnt/wslg ]]; then wslg="yes"; else wslg="no"; fi

  if command -v cmd.exe >/dev/null 2>&1 || [[ -x /mnt/c/Windows/System32/cmd.exe ]]; then
    interop="OK"
  else
    interop="not detected"
  fi

  pid1="$(ps -p 1 -o comm= 2>/dev/null | awk '{$1=$1};1')"
  sys_state="$(systemctl is-system-running 2>/dev/null || true)"
  [[ -n "$sys_state" ]] || sys_state="unavailable"

  user_sys="$(systemctl --user is-system-running 2>/dev/null || true)"
  [[ -n "$user_sys" ]] || user_sys="unavailable"

  if [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]]; then
    user_bus="OK"
  else
    user_bus="not detected"
  fi

  failed="$(systemctl --failed --no-legend --plain 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | awk '{$1=$1};1')"
  user="$(id -un 2>/dev/null || true)"
  uid="$(id -u 2>/dev/null || true)"
  locale="${LANG:-}"
  [[ -n "$locale" ]] || locale="$(locale 2>/dev/null | awk -F= '$1=="LANG"{gsub(/\"/,"",$2);print $2;exit}')"
  timezone="$(cat /etc/timezone 2>/dev/null || true)"
  if getent hosts apt.pop-os.org >/dev/null 2>&1; then dns="OK"; else dns="failed"; fi
  rootfs="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
  desktop="$(desktop_state)"
  if repo_ok; then repos="OK"; else repos="missing/incomplete"; fi

  status="READY"
  [[ "$wsl" == "yes" ]] || status="CHECK"
  [[ "$pid1" == "systemd" ]] || status="CHECK"
  [[ "$sys_state" == "running" || "$sys_state" == "degraded" ]] || status="CHECK"
  [[ "$failed" == "0" ]] || status="CHECK"
  [[ "$dns" == "OK" ]] || status="CHECK"
  [[ "$repos" == "OK" ]] || status="CHECK"

  printf '\n'
  printf '   Pop!_OS 24.04 WSL Base %s\n' "$VERSION"
  printf '============================================\n'
  printf '%-22s %s\n' 'Distribution:' "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")"
  printf '%-22s %s\n' 'Kernel:' "$(value_or_unknown "$kernel")"
  printf '%-22s %s\n' 'WSL:' "$wsl"
  printf '%-22s %s\n' 'WSLg:' "$wslg"
  printf '%-22s %s\n' 'Windows interop:' "$interop"
  printf '%-22s %s\n' 'PID 1:' "$(value_or_unknown "$pid1")"
  printf '%-22s %s\n' 'systemd:' "$sys_state"
  printf '%-22s %s\n' 'User systemd:' "$user_sys"
  printf '%-22s %s\n' 'User D-Bus:' "$user_bus"
  printf '%-22s %s\n' 'Failed units:' "$failed"
  printf '%-22s %s\n' 'User:' "$(value_or_unknown "$user")"
  printf '%-22s %s\n' 'UID:' "$(value_or_unknown "$uid")"
  printf '%-22s %s\n' 'Locale:' "$(value_or_unknown "$locale")"
  printf '%-22s %s\n' 'Timezone:' "$(value_or_unknown "$timezone")"
  printf '%-22s %s\n' 'DNS:' "$dns"
  printf '%-22s %s\n' 'Root filesystem:' "$(value_or_unknown "$rootfs")"
  printf '%-22s %s\n' 'Pop!_OS repositories:' "$repos"
  printf '%-22s %s\n' 'Desktop:' "$desktop"
  printf '\n'
  printf '%-22s %s\n' 'Status:' "$status"
  printf '\n'
}

info() {
  printf '%s %s\n' "$DISTRO" "$VERSION"
  printf 'OS: '
  . /etc/os-release 2>/dev/null || true
  printf '%s\n' "${PRETTY_NAME:-unknown}"
  printf 'Kernel: %s\n' "$(uname -r 2>/dev/null || printf unknown)"
  printf 'Architecture: %s\n' "$(uname -m 2>/dev/null || printf unknown)"
  printf 'systemd PID 1: %s\n' "$( [[ "$(ps -p 1 -o comm= 2>/dev/null | awk '{$1=$1};1')" == systemd ]] && printf yes || printf no )"
  printf 'Desktop: %s\n' "$(desktop_state)"
}

case "${1:-doctor}" in
  doctor) doctor ;;
  info) info ;;
  version|--version|-V) printf '%s %s\n' "$DISTRO" "$VERSION" ;;
  help|--help|-h)
    cat <<EOF
Usage: pop-wsl <command>

Commands:
  doctor    Check the WSL runtime, systemd, DNS and Pop!_OS repositories.
  info      Show basic distribution information.
  version   Show the WSL base version.
EOF
    ;;
  *)
    printf 'Unknown command: %s\n' "$1" >&2
    printf 'Run: pop-wsl help\n' >&2
    exit 2
    ;;
esac
POPWSL

cat > "${TMP_DIR}/sudoers-pop-wsl" <<'EOF'
%sudo ALL=(ALL:ALL) ALL
EOF

log "Installing WSL configuration and helper tools into the rootfs..."
docker exec "$CONTAINER_NAME" mkdir -p /usr/lib/wsl /usr/local/bin /etc/sudoers.d

docker cp "${TMP_DIR}/wsl.conf" "$CONTAINER_NAME:/etc/wsl.conf"
docker cp "${TMP_DIR}/wsl-distribution.conf" "$CONTAINER_NAME:/etc/wsl-distribution.conf"
docker cp "${TMP_DIR}/oobe.sh" "$CONTAINER_NAME:/usr/lib/wsl/oobe.sh"
docker cp "${TMP_DIR}/pop-wsl" "$CONTAINER_NAME:/usr/local/bin/pop-wsl"
docker cp "${TMP_DIR}/sudoers-pop-wsl" "$CONTAINER_NAME:/etc/sudoers.d/90-pop-wsl"

docker exec "$CONTAINER_NAME" /bin/bash -euxo pipefail -c '
  chown root:root /etc/wsl.conf /etc/wsl-distribution.conf /usr/lib/wsl/oobe.sh /usr/local/bin/pop-wsl /etc/sudoers.d/90-pop-wsl
  chmod 0644 /etc/wsl.conf /etc/wsl-distribution.conf
  chmod 0755 /usr/lib/wsl/oobe.sh /usr/local/bin/pop-wsl
  chmod 0440 /etc/sudoers.d/90-pop-wsl

  # WSL/systemd compatibility masks.  The first four were verified by
  # cold-boot testing on Pop!_OS 24.04 under WSL2.
  mkdir -p /etc/systemd/system
  for unit in \
    getty@tty1.service \
    tpm-udev.path \
    tpm-udev.service \
    systemd-binfmt.service \
    systemd-resolved.service \
    systemd-networkd.service \
    NetworkManager.service \
    systemd-tmpfiles-setup.service \
    systemd-tmpfiles-clean.service \
    systemd-tmpfiles-clean.timer \
    systemd-tmpfiles-setup-dev-early.service \
    systemd-tmpfiles-setup-dev.service \
    tmp.mount; do
      ln -sfn /dev/null "/etc/systemd/system/$unit"
  done

  # A terminal-focused base should boot to the multi-user target.
  ln -sfn /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

  # Remove container-only behavior that would interfere with a normal WSL system.
  rm -f /usr/sbin/policy-rc.d
  rm -f /etc/apt/apt.conf.d/docker-clean \
        /etc/apt/apt.conf.d/docker-gzip-indexes \
        /etc/apt/apt.conf.d/docker-no-languages \
        /etc/apt/apt.conf.d/docker-autoremove-suggests
  rm -f /etc/dpkg/dpkg.cfg.d/docker

  # Docker bind-mounts /etc/resolv.conf, /etc/hosts and /etc/hostname.
  # They are removed from the exported tar archive after docker export.

  # A fresh machine identity is created on first boot.
  : > /etc/machine-id
  rm -f /var/lib/dbus/machine-id

  # Do not ship a kernel/initramfs inside a WSL rootfs.
  rm -f /boot/vmlinuz-* /boot/initrd.img-* /boot/initramfs-* 2>/dev/null || true

  # No password hashes are allowed in the distributed rootfs. Lock any hashed accounts.
  if [ -f /etc/shadow ]; then
    awk -F: '\''BEGIN{OFS=FS} {if ($2 == "" || $2 ~ /^\$/) $2="!"; print}'\'' /etc/shadow > /etc/shadow.new
    chown root:shadow /etc/shadow.new 2>/dev/null || chown root:root /etc/shadow.new
    chmod 0640 /etc/shadow.new
    mv /etc/shadow.new /etc/shadow
  fi

  # Keep the image clean and deterministic.
  apt-get clean
  rm -rf /var/lib/apt/lists/*
  rm -rf /tmp/* /var/tmp/*
  rm -f /root/.bash_history
  find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
  chmod 1777 /tmp /var/tmp

  # Final static sanity checks.
  test -s /etc/os-release
  test -s /etc/wsl.conf
  test -s /etc/wsl-distribution.conf
  test -x /usr/lib/wsl/oobe.sh
  test -x /usr/local/bin/pop-wsl
  grep -q "^systemd=true$" /etc/wsl.conf
  grep -q "^defaultUid=1000$" /etc/wsl-distribution.conf
  grep -q "^defaultName=Pop_OS-24.04$" /etc/wsl-distribution.conf
  ! getent passwd 1000 >/dev/null

  # 0.1.1 cold-boot regression checks.
  command -v kmod >/dev/null
  test -f /etc/modules
  for unit in getty@tty1.service tpm-udev.path tpm-udev.service systemd-binfmt.service; do
    test -L "/etc/systemd/system/$unit"
    test "$(readlink "/etc/systemd/system/$unit")" = "/dev/null"
  done
  if [ -L /etc/systemd/system/kmod-static-nodes.service ] && \
     [ "$(readlink /etc/systemd/system/kmod-static-nodes.service)" = "/dev/null" ]; then
    echo "kmod-static-nodes.service must remain enabled." >&2
    exit 24
  fi
'
ok "WSL configuration installed."

# Capture package/systemd metadata before stopping the container.
SYSTEMD_VERSION="$(docker exec "$CONTAINER_NAME" dpkg-query -W -f='${Version}' systemd 2>/dev/null || printf unknown)"
PACKAGE_COUNT="$(docker exec "$CONTAINER_NAME" dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l | awk '{$1=$1};1')"

log "Stopping build container..."
docker stop "$CONTAINER_NAME" >/dev/null

log "Exporting clean rootfs..."
RAW_TAR="${TMP_DIR}/rootfs.tar"
docker export --output "$RAW_TAR" "$CONTAINER_NAME"

# Docker supplies these files as container-specific mounts. Remove their archive
# entries so WSL can generate its own network/host configuration at launch.
for entry in \
  etc/resolv.conf ./etc/resolv.conf \
  etc/hosts ./etc/hosts \
  etc/hostname ./etc/hostname \
  .dockerenv ./.dockerenv; do
  tar --delete --file "$RAW_TAR" "$entry" >/dev/null 2>&1 || true
done

gzip -9 -c "$RAW_TAR" > "$ROOTFS_FILE"
cp --reflink=auto "$ROOTFS_FILE" "$WSL_FILE" 2>/dev/null || cp "$ROOTFS_FILE" "$WSL_FILE"

gzip -t "$ROOTFS_FILE"
gzip -t "$WSL_FILE"

# Validate the archive layout without extracting it.
ARCHIVE_LIST="${TMP_DIR}/archive.list"
tar -tzf "$ROOTFS_FILE" > "$ARCHIVE_LIST"
grep -Eq '^\.?/?etc/wsl\.conf$' "$ARCHIVE_LIST" || die "Archive validation failed: /etc/wsl.conf missing."
grep -Eq '^\.?/?etc/wsl-distribution\.conf$' "$ARCHIVE_LIST" || die "Archive validation failed: /etc/wsl-distribution.conf missing."
grep -Eq '^\.?/?usr/lib/wsl/oobe\.sh$' "$ARCHIVE_LIST" || die "Archive validation failed: OOBE script missing."
grep -Eq '^\.?/?usr/local/bin/pop-wsl$' "$ARCHIVE_LIST" || die "Archive validation failed: pop-wsl missing."
if grep -Eq '^\.?/?etc/resolv\.conf$' "$ARCHIVE_LIST"; then
  die "Archive validation failed: /etc/resolv.conf must not be included."
fi
if grep -Eq '^\.?/?boot/(vmlinuz|initrd\.img|initramfs)' "$ARCHIVE_LIST"; then
  die "Archive validation failed: kernel/initramfs detected under /boot."
fi
ok "Rootfs archive validation passed."

BUILD_UTC="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
ROOTFS_SIZE="$(stat -c '%s' "$ROOTFS_FILE")"

cat > "$README_FILE" <<EOF
Pop!_OS 24.04 WSL Base ${BUILDER_VERSION}
============================================

A clean, desktop-free Pop!_OS 24.04 LTS root filesystem for WSL.

Defaults
--------
OS:             Pop!_OS 24.04 LTS (Noble)
Architecture:   amd64 / x86_64
Locale:         en_US.UTF-8
Timezone:       Etc/UTC
systemd:        enabled
Desktop:        not installed
Default UID:    1000 (created during first-run OOBE)
WSL name:       ${DEFAULT_DISTRO_NAME}

Source
------
OCI image:      ${IMAGE}
Image digest:   ${IMAGE_DIGEST}

The source image is a third-party Pop!_OS container image. Pop!_OS, Ubuntu and
all installed packages remain subject to their respective upstream licenses.

Requirements
------------
WSL 2.4.4 or newer is recommended for the modern .wsl distribution format
and first-run OOBE support.

Install
-------
Option 1: Double-click the .wsl file in Windows File Explorer.

Option 2: From PowerShell:

  wsl --install --from-file .\\${ARTIFACT_BASE}.wsl

Then start it with:

  wsl -d ${DEFAULT_DISTRO_NAME}

First launch
------------
The English OOBE creates a normal UNIX account with UID 1000, asks you to set
a password, and adds the account to the sudo group.

Validation
----------
After first launch:

  pop-wsl doctor
  pop-wsl info
  pop-wsl version

Package management
------------------
The Pop!_OS repositories from the source image are preserved. Update normally:

  sudo apt update
  sudo apt full-upgrade

Desktop policy
--------------
No desktop environment, display manager, X11 server configuration, Wayland
compositor or X410-specific configuration is included. Users may install the
desktop stack of their choice later.

WSL cold-boot compatibility
---------------------------
Version 0.1.1 includes the fixes validated on a clean WSL2 cold boot:

  - kmod is installed and /etc/modules is present.
  - getty@tty1.service is masked because WSL has no conventional tty1 login.
  - tpm-udev.path and tpm-udev.service are masked because the container-derived
    rootfs has no conventional udev-managed TPM device in WSL.
  - systemd-binfmt.service is masked because WSL owns binfmt_misc and exposes
    the rule interface read-only to the guest. Windows interop remains enabled.
  - kmod-static-nodes.service is intentionally NOT masked.

Uninstall
---------
WARNING: This permanently deletes that WSL distribution and all of its data.

  wsl --unregister ${DEFAULT_DISTRO_NAME}
EOF

cat > "$MANIFEST_FILE" <<EOF
Pop!_OS 24.04 WSL Base - Build Manifest
============================================
Builder version:       ${BUILDER_VERSION}
Build time (UTC):      ${BUILD_UTC}
Distribution:          ${DISTRO_PRETTY}
Codename:              noble
Architecture:          amd64 / ${ARCH_NAME}
Source image:          ${IMAGE}
Source image ID:       ${IMAGE_ID}
Source image digest:   ${IMAGE_DIGEST}
Systemd package:       ${SYSTEMD_VERSION}
Installed packages:    ${PACKAGE_COUNT}
Locale:                en_US.UTF-8
Timezone:              Etc/UTC
WSL default name:      ${DEFAULT_DISTRO_NAME}
WSL default UID:       1000
systemd:               enabled
Desktop:               not installed
Rootfs bytes:          ${ROOTFS_SIZE}

Expected Pop!_OS repositories:
  http://apt.pop-os.org/release
  http://apt.pop-os.org/ubuntu
  http://apt.pop-os.org/proprietary

WSL compatibility changes:
  - /etc/wsl.conf added with systemd enabled.
  - /etc/wsl-distribution.conf added with English OOBE.
  - Upstream Docker seed account ubuntu (UID/GID 1000) removed.
  - UID/GID 1000 reserved for first-run user creation.
  - Docker-specific apt/dpkg configuration removed.
  - /usr/sbin/policy-rc.d removed.
  - /etc/resolv.conf omitted so WSL can generate DNS configuration.
  - machine-id reset for first boot.
  - kmod installed and /etc/modules created for kmod-static-nodes.service.
  - getty@tty1.service masked.
  - tpm-udev.path and tpm-udev.service masked.
  - systemd-binfmt.service masked because WSL owns read-only binfmt_misc.
  - kmod-static-nodes.service intentionally left enabled.
  - additional WSL-conflicting systemd units masked.
  - kernel/initramfs files excluded.
  - no desktop environment or display manager installed by this builder.

Artifacts:
  ${ARTIFACT_BASE}.wsl
  ${ARTIFACT_BASE}-rootfs.tar.gz
  README.txt
  MANIFEST.txt
  SHA256SUMS

Note:
The .wsl file and rootfs.tar.gz are intentionally byte-identical gzip-compressed
tar archives. The .wsl extension enables the modern WSL distribution install
experience on supported Windows/WSL versions.
EOF

(
  cd "$RELEASE_DIR"
  sha256sum \
    "${ARTIFACT_BASE}.wsl" \
    "${ARTIFACT_BASE}-rootfs.tar.gz" \
    README.txt \
    MANIFEST.txt \
    > SHA256SUMS
)

if [[ "$(id -u)" -eq 0 && "$INVOKING_USER" != "root" ]]; then
  chown -R "$INVOKING_USER":"$(id -gn "$INVOKING_USER" 2>/dev/null || echo "$INVOKING_USER")" "$RELEASE_DIR" 2>/dev/null || true
fi

printf '\n'
printf '============================================================\n'
printf '  BUILD COMPLETE\n'
printf '============================================================\n'
printf 'Release directory:\n  %s\n\n' "$RELEASE_DIR"
printf 'WSL package:\n  %s\n\n' "$WSL_FILE"
printf 'Rootfs archive:\n  %s\n\n' "$ROOTFS_FILE"
printf 'SHA-256:\n'
sed 's/^/  /' "$SHA_FILE"
printf '\n'
printf 'Next on Windows:\n'
printf '  wsl --install --from-file .\\%s.wsl\n' "$ARTIFACT_BASE"
printf '\n'
printf 'First launch will run the English OOBE and create UID 1000.\n'
printf 'After setup, run: pop-wsl doctor\n'
printf '\n'

if (( KEEP_CONTAINER )); then
  warn "Temporary container kept: $CONTAINER_NAME"
  CONTAINER_CREATED=0
fi

trap - EXIT INT TERM
rm -rf -- "$TMP_DIR"
if (( CONTAINER_CREATED )) && (( ! KEEP_CONTAINER )); then
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

exit 0
