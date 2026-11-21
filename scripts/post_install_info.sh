#!/usr/bin/env bash
# post_install_info.sh - writes a summary file for the admin (no passwords)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

write_post_install_info() {
  local out="/root/apex-install-info.txt"
  local ip
  ip="$(curl -s --max-time 5 https://ifconfig.me || true)"
  [[ -n "$ip" ]] || ip="<server-ip>"
  cat > "$out" <<INFO
Oracle APEX installation summary ($(date '+%Y-%m-%d %H:%M'))

URLs
  APEX sign-in : http://${ip}/ords/apex
  ORDS landing : http://${ip}/ords/_/landing
  Direct Tomcat: http://${ip}:${TOMCAT_HTTP_PORT}/ords/

First login (APEX administration)
  Workspace: internal    User: ADMIN
  Password : the one chosen during installation (not stored here)

Database
  Database ${DB_SID}, pluggable database ${PDB_NAME}, port ${DB_PORT} (closed to outside)
  Service: oracle-free-26ai

Folders
  Install base : ${INSTALL_DIRECTORY}
  ORDS config  : ${ORDS_CONFIG_DIR}
  Logs         : /var/log/oracle-apex-installer/

Check the system: sudo ./scripts/validate.sh
Change the first-login passwords after the first sign-in.
INFO
  chmod 600 "$out"
  ok "Summary written to $out (root only)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root
  init_logging
  load_config
  write_post_install_info
fi
