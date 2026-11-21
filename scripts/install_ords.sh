#!/usr/bin/env bash
# install_ords.sh - Stage: install ORDS and run it on Tomcat
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Step A: get the ORDS zip and find its version
ords_download() {
  local zip="$PROJECT_DIR/packages/ords-latest.zip"
  local url="${ORDS_ZIP_URL:-https://download.oracle.com/otn_software/java/ords/ords-latest.zip}"
  if [[ -f "$zip" ]]; then
    info "ORDS zip already downloaded, skipping download"
  else
    info "Downloading ORDS zip"
    curl -fL --silent --show-error -o "$zip" "$url" || die "ORDS download failed"
  fi
  ORDS_ZIP="$zip"
  ORDS_FOUND_VERSION="$(unzip -p "$zip" NOTICE.txt \
    | grep -o 'Release Notes for Oracle REST Data Services [0-9.]*' \
    | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | head -1 || true)"
  [[ -n "$ORDS_FOUND_VERSION" ]] || die "Could not read the ORDS version from the zip"
  ok "ORDS version in zip: $ORDS_FOUND_VERSION"
}

# Step B: ORDS 26.4 and newer need Tomcat 10+, so stop if Tomcat is 9
check_ords_tomcat() {
  local ords_major="${ORDS_FOUND_VERSION%%.*}"
  local rest="${ORDS_FOUND_VERSION#*.}"
  local ords_minor="${rest%%.*}"
  local tomcat_major="${TOMCAT_VERSION%%.*}"
  if (( ords_major > 26 || (ords_major == 26 && ords_minor >= 4) )) && (( tomcat_major < 10 )); then
    die "ORDS $ORDS_FOUND_VERSION needs Tomcat 10 or newer, but Tomcat $TOMCAT_VERSION is installed"
  fi
  ok "ORDS $ORDS_FOUND_VERSION works with Tomcat $TOMCAT_VERSION"
}

# Step C: unzip ORDS (skip if already unzipped)
ords_extract() {
  ORDS_HOME="${INSTALL_DIRECTORY}/ords"
  if [[ -x "$ORDS_HOME/bin/ords" ]]; then
    info "ORDS already unzipped, skipping"
  else
    info "Unzipping ORDS to $ORDS_HOME"
    mkdir -p "$ORDS_HOME"
    unzip -o -q "$ORDS_ZIP" -d "$ORDS_HOME" || die "ORDS unzip failed"
  fi
  [[ -x "$ORDS_HOME/bin/ords" ]] || die "ords command not found in $ORDS_HOME/bin"
  ok "ORDS ready in $ORDS_HOME"
}

# Step D: create the ORDS schema in the database (skip if config already exists)
ords_install_db() {
  local pool="$ORDS_CONFIG_DIR/databases/default/pool.xml"
  local ords_log_dir="/var/log/ords-install"
  local stage_log="$LOG_DIR/ords_install.log"
  if [[ -f "$pool" ]]; then
    info "ORDS config already exists, skipping ORDS database install"
    return 0
  fi
  mkdir -p "$ORDS_CONFIG_DIR" "$ords_log_dir"
  chown tomcat:tomcat "$ORDS_CONFIG_DIR" "$ords_log_dir"
  chmod 750 "$ORDS_CONFIG_DIR" "$ords_log_dir"

  ask_password SYS_PWD "SYS password"
  ask_password ORDS_PWD "New ORDS_PUBLIC_USER password"
  [[ -n "${SYS_PWD:-}" && -n "${ORDS_PWD:-}" ]] || die "Passwords are empty"

  info "Running ORDS install (passwords are not logged)"
  printf '%s\n%s\n' "$SYS_PWD" "$ORDS_PWD" \
    | runuser -u tomcat -- "$ORDS_HOME/bin/ords" --config "$ORDS_CONFIG_DIR" install \
        --log-folder "$ords_log_dir" --admin-user SYS \
        --db-hostname localhost --db-port "$DB_PORT" --db-servicename "$PDB_NAME" \
        --feature-db-api true --feature-rest-enabled-sql true --feature-sdw true \
        --gateway-mode proxied --gateway-user APEX_PUBLIC_USER \
        --proxy-user --password-stdin >>"$stage_log" 2>&1 \
    || { unset SYS_PWD ORDS_PWD; die "ORDS install failed, see $stage_log"; }
  unset SYS_PWD ORDS_PWD
  [[ -f "$pool" ]] || die "ORDS install finished but $pool is missing"
  ok "ORDS installed in the database"
}
# Step E: copy APEX images and ords.war into Tomcat
ords_deploy() {
  local webapps="${INSTALL_DIRECTORY}/tomcat/webapps"
  local images_src="${INSTALL_DIRECTORY}/apex/images"
  [[ -d "$images_src" ]] || die "APEX images not found in $images_src (run the APEX stage first)"
  mkdir -p "$webapps/i"
  cp -r "$images_src/." "$webapps/i/"
  if cmp -s "$ORDS_HOME/ords.war" "$webapps/ords.war"; then
    info "ords.war already deployed, skipping copy"
  else
    cp "$ORDS_HOME/ords.war" "$webapps/ords.war"
    DEPLOY_CHANGED=1
  fi
  chown -R tomcat:tomcat "$webapps/i" "$webapps/ords.war"
  ok "APEX images and ords.war are in Tomcat"
}

# Step F: tell Tomcat where the ORDS config is (systemd drop-in)
ords_tomcat_config() {
  local dropin_dir="/etc/systemd/system/tomcat.service.d"
  local dropin="$dropin_dir/ords.conf"
  local want
  want="$(printf '[Service]\nEnvironment="JAVA_OPTS=-Dconfig.url=%s"' "$ORDS_CONFIG_DIR")"
  if [[ -f "$dropin" ]] && [[ "$(cat "$dropin")" == "$want" ]]; then
    info "Tomcat drop-in already set, skipping"
    return 0
  fi
  mkdir -p "$dropin_dir"
  printf '%s\n' "$want" > "$dropin"
  systemctl daemon-reload
  DEPLOY_CHANGED=1
  ok "Tomcat now knows the ORDS config path"
}
# Step G: restart Tomcat only if something changed, then check the URL
ords_restart_verify() {
  if [[ "${DEPLOY_CHANGED:-0}" == "1" ]]; then
    info "Restarting Tomcat"
    systemctl restart tomcat || die "Tomcat restart failed"
    sleep 30
  else
    info "Nothing changed, no restart needed"
  fi
  local code="000" i
  for i in 1 2 3 4 5 6; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${TOMCAT_HTTP_PORT}/ords/" || true)"
    [[ "$code" == "200" || "$code" == "302" ]] && break
    sleep 10
  done
  [[ "$code" == "200" || "$code" == "302" ]] || die "ORDS URL returned $code, check Tomcat logs"
  ok "ORDS answers on http://localhost:${TOMCAT_HTTP_PORT}/ords/ (HTTP $code)"
  [[ "$(getenforce)" == "Enforcing" ]] || die "SELinux is not Enforcing"
  if ausearch -m avc -ts recent 2>/dev/null | grep -q 'type=AVC'; then
    warn "SELinux denials found, check: ausearch -m avc -ts recent"
  else
    ok "SELinux is Enforcing and no recent denials"
  fi
}
install_ords() {
  info "=== ORDS stage started ==="
  ords_download
  check_ords_tomcat
  ords_extract
  ords_install_db
  ords_deploy
  ords_tomcat_config
  ords_restart_verify
  ok "=== ORDS stage finished ==="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root
  init_logging
  load_config
  install_ords
fi
