#!/usr/bin/env bash
# Installs Tomcat as a non-root systemd service, opens the firewall port.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_tomcat() {
  local tlog="$LOG_DIR/tomcat_install.log"
  local major="${TOMCAT_VERSION%%.*}"
  local tgz="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
  local home="${INSTALL_DIRECTORY}/tomcat"
  local port="${TOMCAT_HTTP_PORT:-8080}"
  info "Tomcat stage started (version ${TOMCAT_VERSION})"

  [ -n "${TOMCAT_VERSION:-}" ] || die "TOMCAT_VERSION is empty in config.env"
  [ -f /etc/profile.d/java.sh ] || die "Java not configured. Run install_java.sh first"
  source /etc/profile.d/java.sh

  # Service account (no login shell, not root)
  id tomcat >/dev/null 2>&1 || {
    useradd -r -m -d "$home-user" -s /sbin/nologin tomcat >>"$tlog" 2>&1 \
      || die "Could not create tomcat user. See $tlog"
    ok "Created service account: tomcat"
  }

  if [ -x "$home/bin/catalina.sh" ]; then
    ok "Tomcat already installed in $home, skipping download"
  else
    mkdir -p "$INSTALL_DIRECTORY" "$home" "$PROJECT_DIR/packages"
    local pkg="$PROJECT_DIR/packages/$tgz"
    if [ ! -f "$pkg" ]; then
      info "Downloading $tgz"
      curl -fsSL -o "$pkg" "https://dlcdn.apache.org/tomcat/tomcat-${major}/v${TOMCAT_VERSION}/bin/$tgz" \
        || curl -fsSL -o "$pkg" "https://archive.apache.org/dist/tomcat/tomcat-${major}/v${TOMCAT_VERSION}/bin/$tgz" \
        || die "Download failed. Check TOMCAT_VERSION or put $tgz in packages/"
    else
      ok "Using local package $tgz"
    fi
    # Verify checksum
    local sha_url="https://archive.apache.org/dist/tomcat/tomcat-${major}/v${TOMCAT_VERSION}/bin/$tgz.sha512"
    local expected; expected=$(curl -fsSL "$sha_url" 2>/dev/null | awk '{print $1}')
    if [ -n "$expected" ]; then
      [ "$(sha512sum "$pkg" | awk '{print $1}')" = "$expected" ] \
        || die "Checksum mismatch for $tgz"
      ok "Checksum verified"
    else
      warn "Could not fetch checksum, skipping verification"
    fi
    tar -xzf "$pkg" -C "$home" --strip-components=1 >>"$tlog" 2>&1 || die "Extract failed. See $tlog"
    ok "Tomcat extracted to $home"
  fi

  # Permissions: root owns the install, tomcat writes only where needed
  chown -R root:tomcat "$home"
  chmod -R g+r "$home"; find "$home" -type d -exec chmod g+x {} \;
  chmod +x "$home"/bin/*.sh
  for d in logs temp work webapps; do mkdir -p "$home/$d"; chown -R tomcat:tomcat "$home/$d"; done
  chmod 750 "$home/conf"; chmod 640 "$home"/conf/*

  # HTTP port
  if ! grep -q "port=\"${port}\" protocol=\"HTTP/1.1\"" "$home/conf/server.xml"; then
    sed -i "0,/<Connector port=\"[0-9]*\" protocol=\"HTTP\/1.1\"/s//<Connector port=\"${port}\" protocol=\"HTTP\/1.1\"/" "$home/conf/server.xml"
    ok "Tomcat HTTP port set to $port"
  fi

  # systemd service
  cat > /etc/systemd/system/tomcat.service << UNIT
[Unit]
Description=Apache Tomcat
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="CATALINA_HOME=${home}"
Environment="CATALINA_BASE=${home}"
Environment="CATALINA_PID=${home}/temp/tomcat.pid"
ExecStart=${home}/bin/startup.sh
ExecStop=${home}/bin/shutdown.sh
SuccessExitStatus=143
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  command -v restorecon >/dev/null && restorecon -R "$home" /etc/systemd/system/tomcat.service
  systemctl enable --now tomcat >>"$tlog" 2>&1 || die "Tomcat failed to start. See $tlog and: journalctl -u tomcat"

  # Firewall (permanent)
  if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${port}/tcp" >>"$tlog" 2>&1
    firewall-cmd --reload >>"$tlog" 2>&1
    ok "Firewall: ${port}/tcp opened"
  else
    warn "firewalld not running, port not configured"
  fi

  # Verify
  sleep 8
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${port}/")
  [ "$code" = "200" ] || die "Tomcat not responding on port ${port} (HTTP $code). See $tlog"
  ok "Tomcat is running on port ${port} (HTTP 200)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root; init_logging; load_config; install_tomcat
fi
