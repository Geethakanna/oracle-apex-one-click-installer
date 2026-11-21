#!/usr/bin/env bash
# Installs the JDK, sets JAVA_HOME and PATH, verifies the result.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

install_java() {
  local pkg="java-${JAVA_VERSION}-openjdk-devel"
  local jlog="$LOG_DIR/java_install.log"
  info "Java stage started (JDK ${JAVA_VERSION})"

  if rpm -q "$pkg" >/dev/null 2>&1; then
    ok "$pkg already installed, skipping download"
  else
    info "Installing $pkg"
    dnf install -y "$pkg" >>"$jlog" 2>&1 || die "Java install failed. See $jlog"
  fi

  local java_home
  java_home=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
  [ -x "$java_home/bin/java" ] || die "Could not locate JAVA_HOME"

  local profile=/etc/profile.d/java.sh
  local content="export JAVA_HOME=$java_home
export PATH=\$JAVA_HOME/bin:\$PATH"
  if [ "$(cat "$profile" 2>/dev/null)" != "$content" ]; then
    echo "$content" > "$profile"; chmod 644 "$profile"
    ok "JAVA_HOME configured: $java_home"
  else
    ok "JAVA_HOME already configured"
  fi

  "$java_home/bin/java" -version 2>&1 | grep -q "\"${JAVA_VERSION}" \
    || die "Java version check failed (expected ${JAVA_VERSION})"
  ok "Java verified: $("$java_home/bin/java" -version 2>&1 | head -1)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root; init_logging; load_config; install_java
fi
