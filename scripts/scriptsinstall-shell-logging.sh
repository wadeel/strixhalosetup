#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

install -d -m 0755 /var/log/shell-capture
install -d -m 0755 /etc/profile.d

cat > /etc/profile.d/99-shell-logging.sh <<'SCRIPT'
# shellcheck shell=bash
if [[ -n "${PS1-}" ]] && [[ "${TERM-}" != "dumb" ]] && [[ -z "${SHELL_LOGGING_ACTIVE-}" ]]; then
  export SHELL_LOGGING_ACTIVE=1
  _u="${SUDO_USER:-$USER}"
  _d="/var/log/shell-capture/${_u}"
  mkdir -p "$_d"
  chmod 700 "$_d" || true
  _f="${_d}/$(date +%F_%H-%M-%S).log"
  ln -sfn "$_f" "${_d}/latest.log" || true
  script -q -f "$_f"
  exit
fi
SCRIPT

cat > /usr/local/sbin/shell-logging-on <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi
if [[ ! -f /etc/profile.d/99-shell-logging.sh ]]; then
  echo "Logging profile missing. Re-run install-shell-logging.sh"
  exit 1
fi
echo "Shell logging already enabled via /etc/profile.d/99-shell-logging.sh"
SCRIPT

cat > /usr/local/sbin/shell-logging-off <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi
rm -f /etc/profile.d/99-shell-logging.sh
echo "Shell logging disabled for new sessions."
SCRIPT

chmod 0755 /usr/local/sbin/shell-logging-on /usr/local/sbin/shell-logging-off

echo "Installed shell logging profile + toggle helpers."
echo "New login shells will be captured to /var/log/shell-capture/<user>/"