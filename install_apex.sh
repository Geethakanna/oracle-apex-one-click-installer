#!/usr/bin/env bash
# install_apex.sh - ONE-CLICK installer: runs every stage in order
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$PROJECT_ROOT/scripts"
source "$SCRIPTS/common.sh"

# run_stage "name" script function  -> loads the script, runs its function
run_stage() {
  local name="$1" script="$2" func="$3"
  info ">>> Stage: $name"
  source "$SCRIPTS/$script"
  "$func" || die "Stage failed: $name"
  ok "<<< Stage done: $name"
}
main() {
  require_root
  init_logging
  load_config
  info "=== Oracle APEX one-click installer started ==="
  source "$SCRIPTS/preflight.sh"
  run_stage "Preflight checks"   preflight.sh       run_preflight
  run_stage "Java"               install_java.sh    install_java
  run_stage "Tomcat"             install_tomcat.sh  install_tomcat
  run_stage "Database"           install_database.sh install_database
  run_stage "APEX"               install_apex_db.sh install_apex_db
  run_stage "ORDS"               install_ords.sh    install_ords
  run_stage "Apache proxy"       install_proxy.sh   install_proxy
  run_stage "Validation"         validate.sh        run_validation
  ok "=== Installation finished ==="
}

main "$@"
