#!/usr/bin/env bash
set -Eeuo pipefail

PROXY_PORT="${PROXY_PORT:-443}"
PROXY_USER="${PROXY_USER:-wdp}"
PROXY_PASS="${PROXY_PASS:-}"
ALLOW_CIDR="${ALLOW_CIDR:-0.0.0.0/0}"
OUTPUT_FILE="${OUTPUT_FILE:-/root/proxy.txt}"

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf '\n[ERROR] %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "Jalankan sebagai root. Contoh: sudo bash install.sh"
  fi
}

validate_input() {
  case "$PROXY_PORT" in
    ''|*[!0-9]*) fail "PROXY_PORT harus angka" ;;
  esac

  if [ "$PROXY_PORT" -lt 1 ] || [ "$PROXY_PORT" -gt 65535 ]; then
    fail "PROXY_PORT harus 1-65535"
  fi

  if ! printf '%s' "$PROXY_USER" | grep -Eq '^[A-Za-z0-9._-]{1,32}$'; then
    fail "PROXY_USER hanya boleh huruf, angka, titik, underscore, minus. Maks 32 karakter."
  fi
}

generate_password() {
  if [ -n "$PROXY_PASS" ]; then
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    PROXY_PASS="$(openssl rand -base64 18 | tr -d '=+/[:space:]' | cut -c1-18)"
  else
    PROXY_PASS="$(date +%s%N | sha256sum | cut -c1-18)"
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y squid apache2-utils curl ca-certificates
}

stop_alternate_ssh_443() {
  local listeners="$1"
  local ssh_22_listeners=""

  if [ "$PROXY_PORT" != "443" ]; then
    return 1
  fi

  if ! printf '%s' "$listeners" | grep -q '"sshd"'; then
    return 1
  fi

  if ! systemctl is-active --quiet wdp-ssh-443.service; then
    return 1
  fi

  ssh_22_listeners="$(ss -H -ltnp 'sport = :22' 2>/dev/null || true)"
  if ! printf '%s' "$ssh_22_listeners" | grep -q '"sshd"'; then
    printf '%s\n' "$listeners" >&2
    fail "Tidak aman mematikan SSH port 443 karena SSH utama port 22 tidak listening"
  fi

  log "Port 443 dipakai SSH tambahan; disabling wdp-ssh-443.service"
  systemctl disable --now wdp-ssh-443.service >/dev/null || \
    fail "Gagal menonaktifkan wdp-ssh-443.service"

  if systemctl is-active --quiet wdp-ssh-443.service; then
    fail "wdp-ssh-443.service masih aktif setelah dinonaktifkan"
  fi

  log "SSH tambahan port 443 stopped; continuing proxy installation"
}

ensure_port_available() {
  local listeners=""

  if ! command -v ss >/dev/null 2>&1; then
    return
  fi

  listeners="$(ss -H -ltnp "sport = :$PROXY_PORT" 2>/dev/null || true)"
  if [ -z "$listeners" ]; then
    return
  fi

  # Allow a re-run when this installer already configured Squid on the port.
  if printf '%s' "$listeners" | grep -q '"squid"'; then
    return
  fi

  if stop_alternate_ssh_443 "$listeners"; then
    listeners="$(ss -H -ltnp "sport = :$PROXY_PORT" 2>/dev/null || true)"
    if [ -z "$listeners" ]; then
      return
    fi
  fi

  printf '%s\n' "$listeners" >&2
  fail "Port $PROXY_PORT sedang digunakan. Hentikan layanan tersebut atau pilih PROXY_PORT lain."
}

find_auth_helper() {
  for helper in \
    /usr/lib/squid/basic_ncsa_auth \
    /usr/lib/squid3/basic_ncsa_auth \
    /usr/lib64/squid/basic_ncsa_auth; do
    if [ -x "$helper" ]; then
      printf '%s' "$helper"
      return
    fi
  done

  fail "basic_ncsa_auth tidak ditemukan setelah install Squid"
}

configure_squid() {
  local auth_helper="$1"
  local allowed_src="$ALLOW_CIDR"

  if [ "$allowed_src" = "0.0.0.0/0" ]; then
    allowed_src="all"
  fi

  install -o proxy -g proxy -m 0640 /dev/null /etc/squid/passwd
  htpasswd -bc /etc/squid/passwd "$PROXY_USER" "$PROXY_PASS" >/dev/null
  chown proxy:proxy /etc/squid/passwd
  chmod 0640 /etc/squid/passwd

  if [ -f /etc/squid/squid.conf ]; then
    cp /etc/squid/squid.conf "/etc/squid/squid.conf.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > /etc/squid/squid.conf <<EOF
visible_hostname wdp-proxy

auth_param basic program $auth_helper /etc/squid/passwd
auth_param basic realm WDP Proxy
auth_param basic credentialsttl 12 hours
acl authenticated proxy_auth REQUIRED
acl allowed_src src $allowed_src

http_access allow allowed_src authenticated
http_access deny all

http_port 0.0.0.0:$PROXY_PORT

via off
forwarded_for delete
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
request_header_access Cache-Control deny all
reply_header_access X-Cache deny all
reply_header_access X-Cache-Lookup deny all

shutdown_lifetime 1 seconds
cache deny all
access_log /var/log/squid/access.log squid
EOF

  squid -k parse >/dev/null
  systemctl enable squid >/dev/null
  systemctl restart squid
}

test_proxy() {
  local response=""
  local url=""

  for url in \
    https://api.ipify.org \
    https://ifconfig.me/ip \
    https://icanhazip.com; do
    response="$(
      curl -4fsS --max-time 15 \
        --proxy "http://127.0.0.1:$PROXY_PORT" \
        --proxy-user "$PROXY_USER:$PROXY_PASS" \
        "$url" 2>/dev/null | tr -d '[:space:]' || true
    )"

    if printf '%s' "$response" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      log "Local authenticated proxy test passed ($response)"
      return
    fi
  done

  systemctl --no-pager --full status squid >&2 || true
  fail "Squid aktif tetapi request melalui proxy lokal gagal"
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi '^Status: active'; then
    ufw allow "$PROXY_PORT/tcp" >/dev/null || true
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$PROXY_PORT/tcp" >/dev/null || true
    firewall-cmd --reload >/dev/null || true
  fi
}

detect_public_ip() {
  local ip=""

  for url in \
    https://api.ipify.org \
    https://ifconfig.me/ip \
    https://icanhazip.com; do
    ip="$(curl -4fsS --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    if printf '%s' "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      printf '%s' "$ip"
      return
    fi
  done

  hostname -I | awk '{print $1}'
}

print_result() {
  local public_ip="$1"
  local proxy_line="${public_ip}:${PROXY_PORT}@${PROXY_USER}:${PROXY_PASS}"

  {
    printf 'Proxy: %s\n' "$proxy_line"
    printf 'Host : %s\n' "$public_ip"
    printf 'Port : %s\n' "$PROXY_PORT"
    printf 'User : %s\n' "$PROXY_USER"
    printf 'Pass : %s\n' "$PROXY_PASS"
  } > "$OUTPUT_FILE"
  chmod 0600 "$OUTPUT_FILE" || true

  printf '\n'
  printf '============================================================\n'
  printf 'PROXY READY\n'
  printf '============================================================\n'
  printf 'Format : Host IP:Port@Username:Password\n'
  printf 'Proxy  : %s\n' "$proxy_line"
  printf 'Saved  : %s\n' "$OUTPUT_FILE"
  printf 'Test   : curl -x http://%s:%s@%s:%s https://api.ipify.org\n' "$PROXY_USER" "$PROXY_PASS" "$public_ip" "$PROXY_PORT"
  printf '============================================================\n'
}

main() {
  need_root
  validate_input
  ensure_port_available
  log "Installing Squid proxy"
  install_packages
  generate_password
  log "Configuring authenticated proxy on port $PROXY_PORT"
  configure_squid "$(find_auth_helper)"
  open_firewall
  log "Checking service"
  systemctl --no-pager --full status squid | sed -n '1,8p' || true
  test_proxy
  print_result "$(detect_public_ip)"
}

main "$@"
