#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt update
apt -y install dkms git build-essential linux-headers-"$(uname -r)" ethtool

if apt-cache show r8125-dkms >/dev/null 2>&1; then
  apt -y install r8125-dkms
else
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  git clone --depth=1 https://github.com/awesometic/realtek-r8125-dkms.git "$tmpdir/r8125"
  cd "$tmpdir/r8125"
  ./dkms-install.sh
fi

cat > /etc/modprobe.d/blacklist-r8169.conf <<'CONF'
blacklist r8169
options r8169 disable_msi=1
CONF

cat > /etc/modules-load.d/r8125.conf <<'CONF'
r8125
CONF

update-initramfs -u

echo "Done. Reboot recommended."
echo "Post-reboot check: lsmod | grep -E 'r8125|r8169'"
