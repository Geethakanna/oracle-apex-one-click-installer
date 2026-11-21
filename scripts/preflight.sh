#!/usr/bin/env bash
# Preflight checks: privileges, OS, CPU, RAM, disk, network.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MIN_RAM_MB="${MIN_RAM_MB:-3800}"
MIN_DISK_GB="${MIN_DISK_GB:-30}"

check() {  # check "description" command...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "PASS: $desc"; else warn "FAIL: $desc"; FAILED=1; fi
}

run_preflight() {
  FAILED=0
  info "Preflight checks started"

  local os_id os_ver os_name ram_mb disk_gb dir
  os_id=$(. /etc/os-release; echo "$ID")
  os_ver=$(. /etc/os-release; echo "${VERSION_ID%%.*}")
  os_name=$(. /etc/os-release; echo "$PRETTY_NAME")
  ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  dir=$(dirname "${INSTALL_DIRECTORY:-/opt/oracle-apex}")
  disk_gb=$(df -BG --output=avail "$dir" | tail -1 | tr -dc '0-9')

  check "Root privileges"                       test "$(id -u)" -eq 0
  check "OS is Oracle Linux 9 ($os_name)"       test "$os_id" = "ol" -a "$os_ver" = "9"
  check "CPU architecture x86_64 ($(uname -m))" test "$(uname -m)" = "x86_64"
  check "RAM >= ${MIN_RAM_MB} MB (${ram_mb} MB)" test "$ram_mb" -ge "$MIN_RAM_MB"
  check "Disk >= ${MIN_DISK_GB} GB free (${disk_gb} GB)" test "$disk_gb" -ge "$MIN_DISK_GB"
  check "DNS resolution"                        getent hosts www.oracle.com
  check "Internet connectivity"                 curl -sI --max-time 10 https://www.oracle.com

  [ "$FAILED" -eq 0 ] || die "Preflight failed. Fix the items above and re-run."
  ok "Preflight checks passed"
}

# Run directly: sudo ./scripts/preflight.sh
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  require_root; init_logging; load_config; run_preflight
fi
