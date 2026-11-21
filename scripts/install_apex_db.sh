#!/usr/bin/env bash
# Installs Oracle APEX into the PDB, creates the APEX ADMIN user, unlocks APEX_PUBLIC_USER.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OH=/opt/oracle/product/26ai/dbhomeFree

# Run SQL from stdin as SYS in the PDB. Passwords go through stdin, never the process list.
run_sql() {
  local wd="${1:-/tmp}"
  { printf 'whenever sqlerror exit failure\nset define off\nconnect sys/"%s"@localhost:%s/%s as sysdba\n' \
      "$DB_PASSWORD" "${DB_PORT:-1521}" "$PDB_NAME"
    cat; printf 'exit\n'; } \
  | runuser -u oracle -- bash -c "cd '$wd' && ORACLE_HOME=$OH PATH=$OH/bin:\$PATH LD_LIBRARY_PATH=$OH/lib exec sqlplus -s /nolog"
}

check_pw() { [[ "$1" =~ [\"\'\ \\] ]] && die "Password must not contain quotes, spaces or backslashes"; return 0; }

apex_version() {
  printf "set heading off feedback off pagesize 0\nselect 'APEX_OK:'||version from dba_registry where comp_id='APEX' and status='VALID';\n" \
    | run_sql /tmp 2>/dev/null | grep -o 'APEX_OK:.*' | head -1
}

install_apex_db() {
  local alog="$LOG_DIR/apex_install.log"
  local zip="$PROJECT_DIR/packages/apex-latest.zip"
  local apex_dir="${INSTALL_DIRECTORY}/apex"
  info "APEX stage started"

  [ -d "/opt/oracle/oradata/${DB_SID}" ] || die "Database not found. Run install_database.sh first"
  pgrep -f "db_pmon_${DB_SID}" >/dev/null || die "Database is not running"
  [ -n "${APEX_ZIP_URL:-}" ] || die "APEX_ZIP_URL is empty in config.env"

  [ -n "${DB_PASSWORD:-}" ] || ask_password DB_PASSWORD "Database SYS password"
  check_pw "$DB_PASSWORD"

  local v; v=$(apex_version)
  if [ -n "$v" ]; then
    ok "APEX already installed (${v#APEX_OK:}), skipping install"
    fresh_install=0
  else
    fresh_install=1
    command -v unzip >/dev/null || dnf install -y unzip >>"$alog" 2>&1
    mkdir -p "$PROJECT_DIR/packages" "$INSTALL_DIRECTORY"
    if [ ! -f "$zip" ]; then
      info "Downloading APEX"
      curl -fL -o "$zip" "$APEX_ZIP_URL" >>"$alog" 2>&1 || die "APEX download failed. See $alog"
    else
      ok "Using local package apex-latest.zip"
    fi
    if [ -n "$APEX_ZIP_SHA256" ]; then
      [ "$(sha256sum "$zip" | awk '{print $1}')" = "$APEX_ZIP_SHA256" ] || die "APEX checksum mismatch"
      ok "Checksum verified"
    else
      warn "APEX_ZIP_SHA256 not set, skipping checksum verification"
    fi
    rm -rf "$apex_dir"
    unzip -q "$zip" -d "$INSTALL_DIRECTORY" >>"$alog" 2>&1 || die "Unzip failed. See $alog"
    chown -R oracle:oinstall "$apex_dir"

    info "Installing APEX into ${PDB_NAME} (10 to 20 minutes)"
    printf 'set define on\n@apexins.sql SYSAUX SYSAUX TEMP /i/\n' | run_sql "$apex_dir" >>"$alog" 2>&1 \
      || die "APEX installation failed. See $alog"
    v=$(apex_version)
    [ -n "$v" ] || die "APEX install did not complete. See $alog"
    ok "APEX installed (${v#APEX_OK:})"
  fi

  if [ "$fresh_install" = 1 ]; then
  # APEX instance admin (login: ADMIN)
  [ -n "${APEX_ADMIN_PASSWORD:-}" ] || ask_password APEX_ADMIN_PASSWORD "Choose password for the APEX ADMIN user"
  check_pw "$APEX_ADMIN_PASSWORD"
  run_sql /tmp >>"$alog" 2>&1 <<SQL || die "Could not set APEX ADMIN user. See $alog (fallback: run apxchpwd.sql manually)"
begin
  apex_instance_admin.create_or_update_admin_user(
    p_username => 'ADMIN',
    p_email    => '${APEX_ADMIN_EMAIL:-admin@example.com}',
    p_password => '${APEX_ADMIN_PASSWORD}');
  commit;
end;
/
SQL
  ok "APEX ADMIN user configured"

  # APEX_PUBLIC_USER is needed by ORDS
  [ -n "${APEX_PUBLIC_PASSWORD:-}" ] || ask_password APEX_PUBLIC_PASSWORD "Choose password for APEX_PUBLIC_USER"
  check_pw "$APEX_PUBLIC_PASSWORD"
  run_sql /tmp >>"$alog" 2>&1 <<SQL || die "Could not unlock APEX_PUBLIC_USER. See $alog"
alter user APEX_PUBLIC_USER identified by "${APEX_PUBLIC_PASSWORD}" account unlock;
SQL
  ok "APEX_PUBLIC_USER unlocked"
  else
    info "APEX was already installed, skipping ADMIN and APEX_PUBLIC_USER setup"
  fi
  ok "APEX stage complete. Static files: $apex_dir/images"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root; init_logging; load_config; install_apex_db
fi
