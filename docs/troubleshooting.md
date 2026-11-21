# Troubleshooting Guide

Each entry has the problem, the cause and the fix. Logs are in `/var/log/oracle-apex-installer/`.

## 1. SSH session drops during a long install
- **Cause:** the network connection closed while the installer was running.
- **Fix:** run the installer inside `tmux`. After login, type `tmux attach` to come back. Add `ServerAliveInterval 60` to your SSH config.

## 2. SSH key is rejected (Permission denied, publickey)
- **Cause:** wrong key file, wrong user, or wrong file permissions.
- **Fix:** use the private key with `ssh -i <key> opc@<ip>`. Keep the key private (`chmod 600` on Linux). Share only the `.pub` file.

## 3. Database service shows "inactive" in systemd
- **Cause:** Oracle uses an old-style start file, so systemd shows it as generated until it is started with systemctl.
- **Fix:** `sudo systemctl start oracle-free-26ai`. Check with `systemctl is-active oracle-free-26ai`. The installer checks the process `db_pmon_FREE` too.

## 4. APEX rejects the ADMIN password (ORA-20001)
- **Cause:** APEX password rules. Dictionary words and weak passwords are refused.
- **Fix:** use 12 or more characters with letters, numbers and a symbol, and not a common word.

## 5. ORA-01017 invalid credential during the ORDS install
- **Cause:** the SYS password was empty or wrong, for example the shell variable was lost.
- **Fix:** run the installer again and type the SYS password carefully. Never reuse the SYS password for ORDS_PUBLIC_USER.
## 6. ORDS install fails: "An error occurred using --log-folder"
- **Cause:** the ORDS install runs as the user `tomcat`. The folder `/var/log/oracle-apex-installer` is owned by root with mode 750, so `tomcat` cannot enter it.
- **Fix:** the installer uses a separate log folder, `/var/log/ords-install`, owned by `tomcat`.

## 7. Cannot list the Tomcat folder (Permission denied)
- **Cause:** `/opt/oracle-apex/tomcat` is owned by `tomcat` and closed to other users. This is intended.
- **Fix:** use `sudo ls /opt/oracle-apex/tomcat/webapps`.

## 8. ORDS URL gives HTTP 302 with curl
- **Cause:** ORDS redirects to the APEX sign-in page and sets a session cookie. `curl -L` does not keep the cookie.
- **Fix:** 302 means ORDS is working. To follow the redirect, use `curl -c /tmp/cj -b /tmp/cj -L <url>`. A browser works normally.

## 9. Apache cannot reach Tomcat (HTTP 503)
- **Cause:** SELinux blocks Apache from making network connections.
- **Fix:** `sudo setsebool -P httpd_can_network_connect on`. Do not disable SELinux. Check denials with `sudo ausearch -m avc -ts recent`.

## 10. Port 80 works on the server but not from the browser
- **Cause:** the cloud (OCI) ingress rule for port 80 is missing. The server firewall is not the problem.
- **Fix:** ask the network owner to open TCP 80 for your IP. Check the server side with `curl http://localhost/ords/`.

## 11. Re-running the installer asks for a password
- **Cause:** only the SYS password is asked on a re-run, to check whether APEX is already installed. The ADMIN and APEX_PUBLIC_USER setup runs only on a fresh APEX install.
- **Fix:** type the SYS password. Never type a new APEX_PUBLIC_USER password on a re-run, because ORDS keeps the old one in its wallet and would stop connecting.

## 12. Passwords were not set when a command ran
- **Cause:** a password shell variable was empty (new shell or session).
- **Fix:** run the command through the installer, which asks for the password each time. Do not paste passwords into chat or scripts.

## 13. Check everything quickly
Run `sudo ./scripts/validate.sh`. Each `[FAIL]` line names the part to look at first.
