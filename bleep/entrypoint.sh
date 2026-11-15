#!/bin/bash
# Headless BLEEP host: private system bus, bluetoothd, then sshd as pid 1.
set -euo pipefail

mkdir -p /run/sshd /run/dbus /home/bleep/.ssh /home/bleep/.bleep /home/bleep/.local/share/bleep

if [[ ! -f /home/bleep/.ssh/ssh_host_ed25519_key ]]; then
  ssh-keygen -q -t ed25519 -f /home/bleep/.ssh/ssh_host_ed25519_key -N ""
  ssh-keygen -q -t rsa -b 3072 -f /home/bleep/.ssh/ssh_host_rsa_key -N ""
  ssh-keygen -q -t ecdsa -f /home/bleep/.ssh/ssh_host_ecdsa_key -N ""
fi

if [[ ! -s /run/secrets/bleep_ed25519.pub ]]; then
  echo "BLEEP public key is not mounted at /run/secrets/bleep_ed25519.pub" >&2
  exit 1
fi
install -o bleep -g bluetooth -m 600 /run/secrets/bleep_ed25519.pub /home/bleep/.ssh/authorized_keys

chown -R bleep:bluetooth /home/bleep/.bleep /home/bleep/.local
chmod 700 /home/bleep /home/bleep/.ssh
for kind in ed25519 rsa ecdsa; do
  ln -sfn "/home/bleep/.ssh/ssh_host_${kind}_key" "/etc/ssh/ssh_host_${kind}_key"
  ln -sfn "/home/bleep/.ssh/ssh_host_${kind}_key.pub" "/etc/ssh/ssh_host_${kind}_key.pub"
  chown root:root "/home/bleep/.ssh/ssh_host_${kind}_key" "/home/bleep/.ssh/ssh_host_${kind}_key.pub"
  chmod 600 "/home/bleep/.ssh/ssh_host_${kind}_key"
  chmod 644 "/home/bleep/.ssh/ssh_host_${kind}_key.pub"
done
chown bleep:bluetooth /home/bleep/.ssh /home/bleep/.ssh/authorized_keys

# dbus-daemon --fork can return before the socket accepts connections.
# On the 2026-11-10 12:20 UTC boot, bluetoothd and bluealsa got
# "Connection refused" and exited, and sshd stayed up with no bus.
bus_accepts() {
  python3 - "$1" <<'PY'
import socket, sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(0.2)
try:
    sock.connect(sys.argv[1])
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
}

dbus_running() {
  pgrep -a -x dbus-daemon | grep -q -F -- "$1"
}

wait_bus() {
  local path="$1"
  local n
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    if bus_accepts "$path"; then
      return 0
    fi
    sleep 0.2
  done
  echo "D-Bus at ${path} is not accepting connections" >&2
  return 1
}

ensure_system_bus() {
  if bus_accepts /run/dbus/system_bus_socket; then
    return 0
  fi
  if [[ -S /run/dbus/system_bus_socket ]] && ! dbus_running '--system'; then
    rm -f /run/dbus/system_bus_socket
  fi
  if ! dbus_running '--system'; then
    dbus-daemon --system --fork
  fi
  wait_bus /run/dbus/system_bus_socket
}

# AF_BLUETOOTH is rejected (EAFNOSUPPORT) in the container network namespace.
# bluetoothd, obexd, and bluealsa open those sockets, so they join the host netns.
# Their D-Bus connection stays the container system bus.
start_bt() {
  if [[ -e /hostns/net ]]; then
    nsenter --net=/hostns/net "$@" &
  else
    "$@" &
  fi
}

ensure_bluetoothd() {
  if pgrep -x bluetoothd >/dev/null 2>&1; then
    return 0
  fi
  # -E is the switch bleep --check-env documents. Without it, Adapter1.ConnectDevice
  # is absent and gatt-enum falls back to a short discovery.
  ensure_system_bus
  start_bt /usr/sbin/bluetoothd --nodetach -E
}

# obexd 5.72 on Ubuntu talks to the session bus and rejects --experimental.
# The bus is owned by bleep so an SSH session can see DBUS_SESSION_BUS_ADDRESS.
install -d -o bleep -g bluetooth -m 755 /run/bleep-session
session_bus=/run/bleep-session/bus
if ! grep -q '^DBUS_SESSION_BUS_ADDRESS=' /etc/environment; then
  printf 'DBUS_SESSION_BUS_ADDRESS=unix:path=%s\n' "$session_bus" >> /etc/environment
fi

ensure_session_bus() {
  if bus_accepts "$session_bus"; then
    return 0
  fi
  if [[ -S "$session_bus" ]] && ! dbus_running '--session'; then
    rm -f "$session_bus"
  fi
  if ! dbus_running '--session'; then
    runuser -u bleep -- dbus-daemon --session --fork \
      --address="unix:path=${session_bus}" --nopidfile
  fi
  wait_bus "$session_bus"
}

ensure_obexd() {
  if pgrep -x obexd >/dev/null 2>&1; then
    return 0
  fi
  [[ -x /usr/libexec/bluetooth/obexd ]] || return 0
  ensure_session_bus
  local -a obex_env
  obex_env=(env "DBUS_SESSION_BUS_ADDRESS=unix:path=${session_bus}" HOME=/home/bleep /usr/libexec/bluetooth/obexd)
  if [[ -e /hostns/net ]]; then
    nsenter --net=/hostns/net runuser -u bleep -- "${obex_env[@]}" &
  else
    runuser -u bleep -- "${obex_env[@]}" &
  fi
}

ensure_bluealsa() {
  if pgrep -x bluealsa >/dev/null 2>&1; then
    return 0
  fi
  [[ -x /usr/bin/bluealsa ]] || return 0
  # One profile handler. A second stack (PulseAudio or PipeWire) contends for the same endpoints.
  ensure_system_bus
  start_bt /usr/bin/bluealsa -p a2dp-source -p a2dp-sink -p hfp-hf -p hfp-ag -p hsp-hs -p hsp-ag
}

# no-new-privileges blocks sudo, so user bleep cannot nsenter. This daemon
# stays root and runs only sdptool and l2ping in the host netns.
ensure_hostnetd() {
  if pgrep -f '[b]leep-hostnetd' >/dev/null 2>&1; then
    return 0
  fi
  [[ -x /usr/local/sbin/bleep-hostnetd ]] || return 0
  /usr/local/sbin/bleep-hostnetd &
}

# Restarts a daemon that exits after sshd is pid 1. The healthcheck only
# notices a missing bluetoothd; it does not start one.
supervise() {
  while true; do
    ensure_system_bus || true
    ensure_bluetoothd || true
    ensure_session_bus || true
    ensure_obexd || true
    ensure_bluealsa || true
    ensure_hostnetd || true
    sleep 5
  done
}

ensure_system_bus
ensure_bluetoothd
ensure_session_bus
ensure_obexd
ensure_bluealsa
ensure_hostnetd
supervise &

exec /usr/sbin/sshd -D -e \
  -o "HostKey=/home/bleep/.ssh/ssh_host_ed25519_key" \
  -o "HostKey=/home/bleep/.ssh/ssh_host_rsa_key"
