#!/usr/bin/env bash
# Installs Oracle AI Database 26ai Free from RPM and creates the FREE / FREEPDB1 database.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_database() {
  local dlog="$LOG_DIR/database_install.log"
  local rpm_file="${DB_RPM_FILE:-oracle-ai-database-free-26ai-23.26.3-1.el9.x86_64.rpm}"
  local pkg="$PROJECT_DIR/packages/$rpm_file"
  info "Database stage started (Oracle AI Database 26ai Free)"

  if [ -d "/opt/oracle/oradata/${DB_SID}" ] && pgrep -f "db_pmon_${DB_SID}" >/dev/null; then
    ok "Database service already running, skipping"; return 0
  fi

  if ! rpm -q oracle-ai-database-free-26ai >/dev/null 2>&1; then
    mkdir -p "$PROJECT_DIR/packages"
    if [ ! -f "$pkg" ]; then
      [ -n "$DB_RPM_URL" ] || die "RPM not found: $pkg. Copy it there or set DB_RPM_URL in config.env"
      info "Downloading database RPM (about 1.5 GB)"
      curl -fL -o "$pkg" "$DB_RPM_URL" >>"$dlog" 2>&1 || die "Download failed. See $dlog"
    else
      ok "Using local package $rpm_file"
    fi
    if [ -n "$DB_RPM_SHA256" ]; then
      [ "$(sha256sum "$pkg" | awk '{print $1}')" = "$DB_RPM_SHA256" ] || die "Checksum mismatch for $rpm_file"
      ok "Checksum verified"
    else
      warn "DB_RPM_SHA256 not set, skipping checksum verification"
    fi

    info "Installing preinstall package"
    dnf install -y oracle-ai-database-preinstall-26ai >>"$dlog" 2>&1 || die "Preinstall failed. See $dlog"

    info "Installing database software (this takes several minutes)"
    dnf -y localinstall "$pkg" >>"$dlog" 2>&1 || die "Database RPM install failed. See $dlog"
    ok "Database software installed"
  else
    ok "Database software already installed"
  fi

  if [ -z "$DB_PASSWORD" ]; then ask_password DB_PASSWORD "Choose a password for SYS/SYSTEM/PDBADMIN"; fi
  info "Creating database ${DB_SID} / ${PDB_NAME} (this takes several minutes)"
  (echo "$DB_PASSWORD"; echo "$DB_PASSWORD") | /etc/init.d/oracle-free-26ai configure >>"$dlog" 2>&1 \
    || die "Database creation failed. See $dlog"

  systemctl enable oracle-free-26ai >>"$dlog" 2>&1 || warn "Could not enable auto-start"
  systemctl is-active --quiet oracle-free-26ai || /etc/init.d/oracle-free-26ai start >>"$dlog" 2>&1
  sleep 5
  ss -tln | grep -q ":${DB_PORT:-1521} " || die "Listener not on port ${DB_PORT:-1521}. See $dlog"
  ok "Listener is up on port ${DB_PORT:-1521}"

  local out
  out=$(su - oracle -c "export ORACLE_HOME=/opt/oracle/product/26ai/dbhomeFree; \
        echo \"select 'DB_OK' from dual;\" | \$ORACLE_HOME/bin/sqlplus -s sys/\"${DB_PASSWORD}\"@localhost:${DB_PORT:-1521}/${PDB_NAME} as sysdba" 2>>"$dlog")
  echo "$out" | grep -q DB_OK || die "Test query failed. See $dlog"
  ok "Database verified: query on ${PDB_NAME} succeeded"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root; init_logging; load_config; install_database
fi
