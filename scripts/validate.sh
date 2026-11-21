#!/usr/bin/env bash
# validate.sh - final check: prints PASS or FAIL for every part
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
ORACLE_HOME="${ORACLE_HOME:-/opt/oracle/product/26ai/dbhomeFree}"
PASS=0
FAIL=0

# check "name" command...  -> prints PASS or FAIL
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "[PASS] $name"; PASS=$((PASS+1))
  else
    echo "[FAIL] $name"; FAIL=$((FAIL+1))
  fi
}

chk_java()      { java -version; }
chk_db_proc()   { pgrep -f "db_pmon_${DB_SID}"; }
chk_listener()  { ss -tln | grep -q ":${DB_PORT} "; }
chk_fw_no_db()  { ! firewall-cmd --list-all | grep -q "${DB_PORT}"; }
chk_fw_http()   { firewall-cmd --list-services | grep -qw http; }
chk_selinux()   { [[ "$(getenforce)" == "Enforcing" ]]; }
chk_tomcat_user() { ps -C java -o user= | grep -qw tomcat; }
chk_apache_user() { ps -C httpd -o user= | grep -qw apache; }
chk_apex_valid() {
  printf 'alter session set container=%s;\nset heading off feedback off\nselect '"'"'APEX_STATUS:'"'"'||status from dba_registry where comp_id='"'"'APEX'"'"';\n' "$PDB_NAME" \
    | runuser -u oracle -- env ORACLE_HOME="$ORACLE_HOME" ORACLE_SID="$DB_SID" \
        "$ORACLE_HOME/bin/sqlplus" -s "/ as sysdba" | grep -q 'APEX_STATUS:VALID'
}
chk_ords_url()  { local c; c="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${TOMCAT_HTTP_PORT}/ords/")"; [[ "$c" == "200" || "$c" == "302" ]]; }
chk_proxy_url() { local c; c="$(curl -s -o /dev/null -w '%{http_code}' http://localhost/ords/)"; [[ "$c" == "200" || "$c" == "302" ]]; }
chk_images_url(){ [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost/i/apex_ui/css/Core.min.css)" == "200" ]]; }

run_validation() {
  info "=== Validation started ==="
  check "Java is installed"                 chk_java
  check "Database process is running"       chk_db_proc
  check "Listener is up on port ${DB_PORT}" chk_listener
  check "Database service is active"        systemctl is-active --quiet oracle-free-26ai
  check "APEX is installed and VALID"       chk_apex_valid
  check "Tomcat service is active"          systemctl is-active --quiet tomcat
  check "Tomcat runs as user tomcat"        chk_tomcat_user
  check "ORDS answers on Tomcat (8080)"     chk_ords_url
  check "Apache service is active"          systemctl is-active --quiet httpd
  check "Apache workers run as apache"      chk_apache_user
  check "Port 80 reaches ORDS"              chk_proxy_url
  check "APEX images load through port 80"  chk_images_url
  check "Firewall allows http (80)"         chk_fw_http
  check "Firewall does NOT open ${DB_PORT}" chk_fw_no_db
  check "SELinux is Enforcing"              chk_selinux
  check "Database auto-starts at boot"      systemctl is-enabled --quiet oracle-free-26ai
  check "Tomcat auto-starts at boot"        systemctl is-enabled --quiet tomcat
  check "Apache auto-starts at boot"        systemctl is-enabled --quiet httpd
  echo "-----------------------------"
  echo "PASSED: $PASS   FAILED: $FAIL"
  if (( FAIL == 0 )); then ok "ALL CHECKS PASSED"; else warn "$FAIL CHECK(S) FAILED"; return 1; fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root
  init_logging
  load_config
  run_validation
fi
