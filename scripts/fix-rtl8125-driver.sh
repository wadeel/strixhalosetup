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

install -d -m 0755 /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'CONF'
network: {config: disabled}
CONF

install -d -m 0755 /etc/netplan
if compgen -G '/etc/netplan/*.yaml' >/dev/null; then
  backup_dir="/etc/netplan/backup-before-r8125-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$backup_dir"
  cp -a /etc/netplan/*.yaml "$backup_dir/"
  echo "Backed up existing netplan YAML files to $backup_dir"
fi

r8125_if=""
mapfile -t all_ifaces < <(ls /sys/class/net)
for iface in "${all_ifaces[@]}"; do
  [[ "$iface" == "lo" ]] && continue
  driver="$(ethtool -i "$iface" 2>/dev/null | awk '/^driver:/ {print $2}')"
  if [[ "$driver" == "r8125" ]]; then
    r8125_if="$iface"
    break
  fi
done

mapfile -t r8169_ifaces < <(
  for iface in "${all_ifaces[@]}"; do
    [[ "$iface" == "lo" ]] && continue
    driver="$(ethtool -i "$iface" 2>/dev/null | awk '/^driver:/ {print $2}')"
    if [[ "$driver" == "r8169" ]]; then
      echo "$iface"
    fi
  done
)

cat > /etc/netplan/99-r8125-static.yaml <<'NETPLAN_HEADER'
network:
  version: 2
  renderer: networkd
  ethernets:
NETPLAN_HEADER

if [[ -n "$r8125_if" ]]; then
  cat >> /etc/netplan/99-r8125-static.yaml <<NETPLAN_8125
    ${r8125_if}:
      dhcp4: false
      dhcp6: false
      addresses:
        - 10.0.0.99/22
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses:
          - 10.0.0.1
      optional: false
NETPLAN_8125
else
  cat >> /etc/netplan/99-r8125-static.yaml <<'NETPLAN_8125_FALLBACK'
    nic8125:
      match:
        driver: r8125
      dhcp4: false
      dhcp6: false
      addresses:
        - 10.0.0.99/22
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses:
          - 10.0.0.1
      optional: false
NETPLAN_8125_FALLBACK
fi

if (( ${#r8169_ifaces[@]} > 0 )); then
  for iface in "${r8169_ifaces[@]}"; do
    cat >> /etc/netplan/99-r8125-static.yaml <<NETPLAN_8169
    ${iface}:
      dhcp4: false
      dhcp6: false
      link-local: []
      optional: true
NETPLAN_8169
  done
else
  cat >> /etc/netplan/99-r8125-static.yaml <<'NETPLAN_8169_FALLBACK'
    nic8169:
      match:
        driver: r8169
      dhcp4: false
      dhcp6: false
      link-local: []
      optional: true
NETPLAN_8169_FALLBACK
fi

if [[ -f /etc/hosts ]]; then
  sed -i 's/10\.0\.0\.98/10.0.0.99/g' /etc/hosts
fi

chmod 600 /etc/netplan/99-r8125-static.yaml
netplan generate
netplan apply

if command -v ip >/dev/null 2>&1; then
  ip -4 addr flush dev "$r8125_if" 2>/dev/null || true
  ip -4 addr add 10.0.0.99/22 dev "$r8125_if" 2>/dev/null || true
fi

echo "Done. Ubuntu network config updated for 10.0.0.99/22 via 10.0.0.1 on r8125."
echo "Cloud-init network config is disabled to keep this persistent across reboots."
echo "Post-checks:"
echo "  ip -4 addr | grep 10.0.0.99"
echo "  ip route | grep default"
echo "  lsmod | grep -E 'r8125|r8169'"
