#!/usr/bin/env bash
# install_proxy.sh - Stage: Apache httpd as reverse proxy (port 80 -> Tomcat 8080)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Step A: install Apache (skip if already installed)
proxy_install() {
  if rpm -q httpd >/dev/null 2>&1; then
    info "Apache httpd already installed, skipping"
  else
    info "Installing Apache httpd"
    dnf install -y httpd >>"$LOG_DIR/proxy_install.log" 2>&1 || die "httpd install failed"
  fi
  rpm -q httpd >/dev/null 2>&1 || die "httpd is not installed"
  ok "Apache httpd is installed"
}

# Step B: write the proxy settings (skip if already correct)
proxy_config() {
  local conf="/etc/httpd/conf.d/apex-proxy.conf"
  local want
  want="$(printf '%s\n' \
    'ProxyPreserveHost On' \
    'ProxyPass /ords http://localhost:'"${TOMCAT_HTTP_PORT}"'/ords' \
    'ProxyPassReverse /ords http://localhost:'"${TOMCAT_HTTP_PORT}"'/ords' \
    'ProxyPass /i http://localhost:'"${TOMCAT_HTTP_PORT}"'/i' \
    'ProxyPassReverse /i http://localhost:'"${TOMCAT_HTTP_PORT}"'/i' \
    'RedirectMatch ^/$ /ords/')"
  if [[ -f "$conf" ]] && [[ "$(cat "$conf")" == "$want" ]]; then
    info "Proxy settings already in place, skipping"
    return 0
  fi
  printf '%s\n' "$want" > "$conf"
  PROXY_CHANGED=1
  ok "Wrote proxy settings to $conf"
}
# Step C: let Apache talk to Tomcat in SELinux, and open port 80
proxy_security() {
  if [[ "$(getsebool httpd_can_network_connect)" == *"--> on" ]]; then
    info "SELinux setting httpd_can_network_connect already on, skipping"
  else
    setsebool -P httpd_can_network_connect on || die "setsebool failed"
    ok "SELinux: Apache is allowed to connect to Tomcat"
  fi
  if firewall-cmd --permanent --query-service=http >/dev/null 2>&1; then
    info "Firewall already allows port 80, skipping"
  else
    firewall-cmd --permanent --add-service=http >/dev/null || die "firewall rule failed"
    firewall-cmd --reload >/dev/null
    ok "Firewall: port 80 opened"
  fi
}

# Step D: start Apache, check the config first
proxy_start() {
  apachectl configtest >>"$LOG_DIR/proxy_install.log" 2>&1 || die "Apache config test failed, see $LOG_DIR/proxy_install.log"
  systemctl enable httpd >/dev/null 2>&1
  if systemctl is-active --quiet httpd; then
    if [[ "${PROXY_CHANGED:-0}" == "1" ]]; then
      systemctl restart httpd || die "httpd restart failed"
    fi
  else
    systemctl start httpd || die "httpd start failed"
  fi
  ok "Apache is running"
}

# Step E: check that port 80 reaches ORDS, and Apache is not root
proxy_verify() {
  local code="000" i
  for i in 1 2 3 4 5; do
    code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost/ords/ || true)"
    [[ "$code" == "200" || "$code" == "302" ]] && break
    sleep 5
  done
  [[ "$code" == "200" || "$code" == "302" ]] || die "Port 80 returned $code"
  ok "Port 80 reaches ORDS (HTTP $code)"
  local users
  users="$(ps -C httpd -o user= | sort -u | tr '\n' ' ')"
  info "Apache processes run as: $users"
  [[ "$(getenforce)" == "Enforcing" ]] || die "SELinux is not Enforcing"
  ok "SELinux is still Enforcing"
}
install_proxy() {
  info "=== Proxy stage started ==="
  proxy_install
  proxy_config
  proxy_security
  proxy_start
  proxy_verify
  ok "=== Proxy stage finished ==="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root
  init_logging
  load_config
  install_proxy
fi
