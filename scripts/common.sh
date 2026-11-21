
#!/usr/bin/env bash
# Shared helpers used by every installer script.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-/var/log/oracle-apex-installer}"
MAIN_LOG="$LOG_DIR/installation_$(date +%Y_%m_%d).log"

init_logging() {
  mkdir -p "$LOG_DIR" && chmod 750 "$LOG_DIR"
  touch "$MAIN_LOG" && chmod 640 "$MAIN_LOG"
}

log() {
  local level="$1"; shift
  echo "[$(date '+%F %T')] [$level] $*" | tee -a "$MAIN_LOG"
}
info() { log INFO "$*"; }
ok()   { log OK   "$*"; }
warn() { log WARN "$*"; }
die()  { log ERROR "$*"; echo "See log: $MAIN_LOG"; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || { echo "Run with: sudo $0"; exit 1; }
}

load_config() {
  local cfg="${CONFIG_FILE:-$PROJECT_DIR/config/config.env}"
  [ -f "$cfg" ] || die "Config file not found: $cfg"
  set -a; . "$cfg"; set +a
}

# Passwords are asked at runtime, never stored in files or logs.
ask_password() {
  local var="$1" prompt="$2" p1 p2
  while true; do
    read -rsp "$prompt: " p1; echo
    read -rsp "Confirm: " p2; echo
    [ -n "$p1" ] && [ "$p1" = "$p2" ] && break
    echo "Passwords empty or not matching, try again."
  done
  export "$var=$p1"
}
