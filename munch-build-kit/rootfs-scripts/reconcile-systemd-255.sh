#!/bin/bash
# Reconcile the apt package set with the systemd 255 runtime used on munch.
#
# The K40S runs an Android 4.19 kernel. systemd 258 raised its minimum kernel
# baseline to 5.4, and on this kernel systemd 259 units end at Result=resources.
# The runtime was therefore pinned to Ubuntu 24.04's systemd 255.4, but the
# resolute libsystemd-dev/libudev-dev and netplan packages were left at versions
# that require the newer runtime. apt then refuses every new install with four
# unmet dependencies.
#
# This script keeps the running systemd at 255.4 and makes the package metadata
# consistent:
#   * install the matching 255.4 libsystemd-dev and libudev-dev;
#   * repack netplan with the same binaries and systemd (>= 255~) as its
#     dependency, versioned +rungic255.1;
#   * pin the systemd 255 stack and hold the affected packages so a routine
#     apt upgrade cannot pull systemd 259 back in.
#
# It never restarts the container or replaces the running systemd. Run it inside
# the Rungic container as root. See docs/123-munch-systemd-255.md.
#
# Usage:
#   reconcile-systemd-255.sh --check      # report only, exit 1 if inconsistent
#   reconcile-systemd-255.sh --dry-run    # download, repack and verify; change nothing
#   reconcile-systemd-255.sh --apply      # apply the reconciliation
#   reconcile-systemd-255.sh --rollback   # restore the pre-reconcile packages
#
# Options:
#   --deb-dir DIR   use pre-downloaded debs from DIR instead of the network
#   --work DIR      working/backup directory (default /var/tmp/rungic-apt-reconcile)
#
set -euo pipefail

readonly SYSTEMD_VERSION="255.4-1ubuntu8.17"
readonly DEV_VERSION="255.4-1ubuntu8.17"
readonly NETPLAN_VERSION="1.2-1ubuntu5.1"
readonly REPACK_VERSION="${NETPLAN_VERSION}+rungic255.1"
readonly PIN_FILE="/etc/apt/preferences.d/rungic-systemd-255"

WORK="${WORK:-/var/tmp/rungic-apt-reconcile}"
DEB_DIR=""
MODE="check"

SYSTEMD_PACKAGES=(
  systemd systemd-sysv systemd-dev libsystemd0 libsystemd-shared
  libpam-systemd libnss-systemd udev libudev1
)
DEV_PACKAGES=(libsystemd-dev libudev-dev)
NETPLAN_PACKAGES=(netplan.io netplan-generator libnetplan1 python3-netplan)
HOLD_PACKAGES=("${SYSTEMD_PACKAGES[@]}" "${DEV_PACKAGES[@]}" "${NETPLAN_PACKAGES[@]}")

# Exact inputs verified on 2026-10-23. The dev packages are no longer in the
# noble-updates pool (superseded by 8.18), so Launchpad's archive is used.
DEV_URLS=(
  "https://launchpad.net/ubuntu/+archive/primary/+files/libsystemd-dev_${DEV_VERSION}_arm64.deb"
  "https://launchpad.net/ubuntu/+archive/primary/+files/libudev-dev_${DEV_VERSION}_arm64.deb"
)
DEV_SHA256=(
  "865d76a9b8cdd8dbb3c6325a935acf2e13605a1fb4de5815ea1147c014c4e2ef"
  "e2dd343cbb11bde45679771d7580d69abffa87c6570e6f58c045bfdfbb9b5242"
)
NETPLAN_URLS=(
  "http://ports.ubuntu.com/ubuntu-ports/pool/main/n/netplan.io/netplan.io_${NETPLAN_VERSION}_arm64.deb"
  "http://ports.ubuntu.com/ubuntu-ports/pool/main/n/netplan.io/netplan-generator_${NETPLAN_VERSION}_arm64.deb"
)
NETPLAN_SHA256=(
  "4c6bbf9b22c0983ec4efc6cc4719b70278beff5e165746edd87a284f15b3af5e"
  "78b5d38f9a8be96414c8a230c0514bbfcc3ddb7f29d1fd3450f673080799c1ec"
)

say()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    MODE="check" ;;
    --dry-run)  MODE="dry-run" ;;
    --apply)    MODE="apply" ;;
    --rollback) MODE="rollback" ;;
    --deb-dir)  DEB_DIR="${2:?--deb-dir needs a directory}"; shift ;;
    --work)     WORK="${2:?--work needs a directory}"; shift ;;
    -h|--help)  usage ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
  shift
done

pkg_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

is_reconciled() {
  [ "$(pkg_version systemd)" = "$SYSTEMD_VERSION" ] || return 1
  [ "$(pkg_version libsystemd-dev)" = "$DEV_VERSION" ] || return 1
  [ "$(pkg_version libudev-dev)" = "$DEV_VERSION" ] || return 1
  [ "$(pkg_version netplan.io)" = "$REPACK_VERSION" ] || return 1
  [ "$(pkg_version netplan-generator)" = "$REPACK_VERSION" ] || return 1
  [ -f "$PIN_FILE" ] || return 1
}

preflight() {
  [ "$(id -u)" = 0 ] || die "run as root inside the Rungic container"
  [ -r /etc/os-release ] || die "/etc/os-release is missing"
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${VERSION_ID:-}" = "26.04" ] || die "expected Ubuntu 26.04, found ${VERSION_ID:-unknown}"
  local running
  running=$(systemctl show -p Version --value 2>/dev/null || true)
  [ "$running" = "$SYSTEMD_VERSION" ] ||
    die "running systemd is ${running:-unknown}, expected ${SYSTEMD_VERSION}; refusing to touch a different runtime"
  command -v dpkg-deb >/dev/null || die "dpkg-deb is missing"
  command -v apt-get >/dev/null || die "apt-get is missing"
  command -v sha256sum >/dev/null || die "sha256sum is missing"
  if command -v fuser >/dev/null && fuser -s /var/lib/dpkg/lock-frontend 2>/dev/null; then
    die "another apt/dpkg process holds the dpkg lock"
  fi
  mkdir -p "$WORK"
  # Large temporary files belong on the rootfs, not the /tmp tmpfs.
  export TMPDIR=/var/tmp
}

fetch() {
  local url="$1" sha="$2" out="$3"
  if [ -f "$out" ] && printf '%s  %s\n' "$sha" "$out" | sha256sum -c - >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$DEB_DIR" ] && [ -f "$DEB_DIR/$(basename "$out")" ]; then
    cp -f "$DEB_DIR/$(basename "$out")" "$out"
  else
    command -v curl >/dev/null || die "curl is missing (or pass --deb-dir)"
    say "downloading $(basename "$out")"
    curl -fL --retry 3 --connect-timeout 20 --max-time 180 -o "$out" "$url" ||
      die "download failed: $url"
  fi
  printf '%s  %s\n' "$sha" "$out" | sha256sum -c - ||
    die "checksum mismatch: $out"
}

list_tree() {
  local dir="$1"
  (
    cd "$dir"
    find . -type f -print0 | sort -z | xargs -0 -r sha256sum
    find . -type l -printf '%p -> %l\n' | sort
  )
}

repack_netplan() {
  local src="$1" out="$2" name="$3"
  local tmp="$WORK/repack-$name"
  rm -rf "$tmp"
  dpkg-deb -R "$src" "$tmp"
  sed -i 's/systemd (>= 258~)/systemd (>= 255~)/g' "$tmp/DEBIAN/control"
  sed -i "s/^Version: .*/Version: ${REPACK_VERSION}/" "$tmp/DEBIAN/control"
  grep -q 'systemd (>= 255~)' "$tmp/DEBIAN/control" ||
    die "could not relax the systemd dependency in $name"
  dpkg-deb --build --root-owner-group "$tmp" "$out" >/dev/null
  # The binaries must be byte-identical; only the dependency metadata changes.
  local a="$WORK/payload-orig-$name" b="$WORK/payload-repack-$name"
  rm -rf "$a" "$b"; mkdir -p "$a" "$b"
  dpkg-deb -x "$src" "$a"
  dpkg-deb -x "$out" "$b"
  list_tree "$a" > "$WORK/$name.orig.list"
  list_tree "$b" > "$WORK/$name.repack.list"
  if ! diff -u "$WORK/$name.orig.list" "$WORK/$name.repack.list" >/dev/null; then
    die "repacked $name payload differs from the original; refusing to install"
  fi
  say "repacked $name ($(wc -l < "$WORK/$name.orig.list") payload entries verified)"
}

write_pin() {
  cat > "$PIN_FILE" <<'PIN'
# K40S (munch) runs an Android 4.19 kernel, below systemd 258's 5.4 baseline.
# The runtime was pinned to Ubuntu 24.04's systemd 255.4 on 2026-10-01. The resolute
# libsystemd-dev/libudev-dev and netplan packages were reconciled to that runtime on
# 2026-10-23: dev headers downgraded to the matching 255.4, and netplan repacked with
# the same binaries and systemd (>= 255~) instead of (>= 258~).
# These pins keep apt from pulling systemd 259 back in (which breaks services here).
Package: systemd systemd-sysv systemd-dev libsystemd0 libsystemd-shared libpam-systemd libnss-systemd udev libudev1
Pin: version 255.4-1ubuntu8.17
Pin-Priority: 1001

Package: libsystemd-dev libudev-dev
Pin: version 255.4-1ubuntu8.17
Pin-Priority: 1001

Package: netplan.io netplan-generator libnetplan1 python3-netplan
Pin: version 1.2-1ubuntu5.1+rungic255.1
Pin-Priority: 1001
PIN
  chmod 644 "$PIN_FILE"
}

backup_state() {
  local dir="$WORK/backup/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  cp -a /var/lib/dpkg/status "$dir/status"
  cp -a /var/lib/dpkg/status-old "$dir/status-old" 2>/dev/null || true
  cp -a /var/lib/apt/extended_states "$dir/extended_states" 2>/dev/null || true
  dpkg -l > "$dir/dpkg-l.txt"
  apt-mark showhold > "$dir/holds.txt"
  cp -a "$PIN_FILE" "$dir/pin" 2>/dev/null || true
  # Keep the current dev packages for --rollback (they are resolute 259.5).
  (cd "$dir" && apt-get download "libsystemd-dev=$(pkg_version libsystemd-dev)" \
      "libudev-dev=$(pkg_version libudev-dev)" >/dev/null 2>&1) || \
    warn "could not cache the current dev packages; --rollback will need --deb-dir"
  cp -f "$WORK/netplan.io_${NETPLAN_VERSION}_arm64.deb" "$dir/" 2>/dev/null || true
  cp -f "$WORK/netplan-generator_${NETPLAN_VERSION}_arm64.deb" "$dir/" 2>/dev/null || true
  printf '%s\n' "$dir" > "$WORK/last-backup"
  say "backup: $dir"
}

check() {
  local failed=0
  for p in systemd libsystemd-dev libudev-dev netplan.io netplan-generator; do
    printf '%-18s %s\n' "$p" "$(pkg_version "$p")"
  done
  [ "$(pkg_version systemd)" = "$SYSTEMD_VERSION" ] || { warn "systemd is not ${SYSTEMD_VERSION}"; failed=1; }
  [ "$(pkg_version libsystemd-dev)" = "$DEV_VERSION" ] || { warn "libsystemd-dev is not ${DEV_VERSION}"; failed=1; }
  [ "$(pkg_version libudev-dev)" = "$DEV_VERSION" ] || { warn "libudev-dev is not ${DEV_VERSION}"; failed=1; }
  [ "$(pkg_version netplan.io)" = "$REPACK_VERSION" ] || { warn "netplan.io is not ${REPACK_VERSION}"; failed=1; }
  [ "$(pkg_version netplan-generator)" = "$REPACK_VERSION" ] || { warn "netplan-generator is not ${REPACK_VERSION}"; failed=1; }
  if [ -f "$PIN_FILE" ] && [ "$(grep -c 'Pin-Priority: 1001' "$PIN_FILE")" = 3 ]; then
    say "pin: $PIN_FILE ok"
  else
    warn "pin file missing or incomplete: $PIN_FILE"; failed=1
  fi
  local holds
  holds=$(apt-mark showhold)
  for p in "${HOLD_PACKAGES[@]}"; do
    grep -qx "$p" <<<"$holds" || { warn "$p is not on hold"; failed=1; }
  done
  if apt-get check >/dev/null 2>&1; then say "apt-get check: ok"; else warn "apt-get check failed"; failed=1; fi
  if apt-get install -s --no-install-recommends tree 2>&1 | grep -q '^E:'; then
    warn "apt cannot resolve a new install"; failed=1
  else
    say "apt install simulation: ok"
  fi
  [ "$failed" = 0 ] || return 1
  say "reconciled"
}

prepare_inputs() {
  say "preparing ${WORK}"
  local i
  for i in "${!DEV_URLS[@]}"; do
    fetch "${DEV_URLS[$i]}" "${DEV_SHA256[$i]}" \
      "$WORK/$(basename "${DEV_URLS[$i]}")"
  done
  for i in "${!NETPLAN_URLS[@]}"; do
    fetch "${NETPLAN_URLS[$i]}" "${NETPLAN_SHA256[$i]}" \
      "$WORK/$(basename "${NETPLAN_URLS[$i]}")"
  done
}

repack_inputs() {
  local netplan_deb generator_deb
  netplan_deb="$WORK/netplan.io_${NETPLAN_VERSION}_arm64.deb"
  generator_deb="$WORK/netplan-generator_${NETPLAN_VERSION}_arm64.deb"
  repack_netplan "$netplan_deb" \
    "$WORK/netplan.io_${REPACK_VERSION}_arm64.deb" netplan.io
  repack_netplan "$generator_deb" \
    "$WORK/netplan-generator_${REPACK_VERSION}_arm64.deb" netplan-generator
}

dry_run() {
  preflight
  prepare_inputs
  repack_inputs
  say "dry run: inputs verified and netplan repacked; nothing installed"
}

apply() {
  preflight
  if is_reconciled && apt-get check >/dev/null 2>&1; then
    say "already reconciled; ensuring pin and holds"
    write_pin
    apt-mark hold "${HOLD_PACKAGES[@]}" >/dev/null
    check
    return 0
  fi

  prepare_inputs
  backup_state
  repack_inputs

  say "installing the matching 255.4 development packages"
  dpkg -i "$WORK/libsystemd-dev_${DEV_VERSION}_arm64.deb" \
          "$WORK/libudev-dev_${DEV_VERSION}_arm64.deb"
  say "installing the repacked netplan"
  dpkg -i "$WORK/netplan.io_${REPACK_VERSION}_arm64.deb" \
          "$WORK/netplan-generator_${REPACK_VERSION}_arm64.deb"

  write_pin
  apt-mark hold "${HOLD_PACKAGES[@]}" >/dev/null
  check
  say "done; the running systemd was not restarted"
}

rollback() {
  preflight
  local dir=""
  [ -f "$WORK/last-backup" ] && dir=$(cat "$WORK/last-backup")
  [ -n "$dir" ] && [ -d "$dir" ] || die "no backup recorded in $WORK/last-backup"
  say "restoring packages from $dir"
  local files=()
  local f
  for f in "$dir"/libsystemd-dev_*.deb "$dir"/libudev-dev_*.deb \
           "$dir"/netplan.io_*.deb "$dir"/netplan-generator_*.deb; do
    [ -f "$f" ] && files+=("$f")
  done
  [ "${#files[@]}" -gt 0 ] || die "backup does not contain the original debs"
  dpkg -i "${files[@]}"
  if [ -f "$dir/pin" ]; then
    cp -a "$dir/pin" "$PIN_FILE"
  else
    rm -f "$PIN_FILE"
  fi
  if [ -f "$dir/holds.txt" ]; then
    local p
    for p in "${HOLD_PACKAGES[@]}"; do
      grep -qx "$p" "$dir/holds.txt" || apt-mark unhold "$p" >/dev/null
    done
  else
    apt-mark unhold "${HOLD_PACKAGES[@]}" >/dev/null
  fi
  say "rolled back; apt is intentionally back to the pre-reconcile state"
}

case "$MODE" in
  check)    preflight; check ;;
  dry-run)  dry_run ;;
  apply)    apply ;;
  rollback) rollback ;;
esac
