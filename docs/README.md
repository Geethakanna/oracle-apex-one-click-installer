# Oracle APEX One-Click Linux Environment Installer

A Bash installer that sets up a full Oracle APEX environment on a fresh Oracle Linux 9 server with one command.

## What gets installed

| Part | Version | Role |
|------|---------|------|
| Java | OpenJDK 17 | Runs Tomcat and ORDS |
| Oracle AI Database Free | 26ai (FREE / FREEPDB1) | Stores data |
| Oracle APEX | 26.2 | Low-code app builder |
| ORDS | latest (26.3.x) | Connects the web to the database and APEX |
| Tomcat | 9.0.124 | Runs ORDS (dedicated user `tomcat`) |
| Apache httpd | 2.4 | Reverse proxy on port 80 |

## Requirements

- Oracle Linux 9, x86_64
- At least 4 GB RAM and 30 GB free disk
- Internet access (downloads Java, Tomcat, APEX, ORDS)
- A user with `sudo`
- Ports: 80 open in the cloud firewall. 8080 is optional (direct Tomcat access). Port 1521 stays closed.

## How to run

```bash
git clone <your-repo-url> apex-installer
cd apex-installer
cp config/config.env.example config/config.env   # then edit if needed
sudo ./install_apex.sh
```

Run it inside `tmux` so a dropped SSH session does not stop it.

The installer asks for passwords while it runs. They are typed hidden and never written to logs or config files.
## Configuration (config/config.env)

All settings are in `config/config.env`. Copy `config/config.env.example` and edit it. There are no passwords in this file.

| Key | Meaning |
|-----|---------|
| `INSTALL_DIRECTORY` | Base folder for Tomcat, APEX and ORDS (default `/opt/oracle-apex`) |
| `DB_SID`, `PDB_NAME`, `DB_PORT` | Database name, pluggable database, listener port |
| `DB_RPM_URL`, `DB_RPM_FILE`, `DB_RPM_SHA256` | Database package and its checksum |
| `APEX_VERSION`, `APEX_ZIP_URL`, `APEX_ADMIN_EMAIL` | APEX download and admin email |
| `ORDS_CONFIG_DIR` | Where ORDS keeps its settings (default `/etc/ords`) |
| `JAVA_VERSION`, `TOMCAT_VERSION`, `TOMCAT_HTTP_PORT` | Java and Tomcat settings |

Optional: `ORDS_ZIP_URL` overrides the ORDS download link.

## Stages

`install_apex.sh` runs these stages in order and stops at the first failure.

| Stage | Script | What it does |
|-------|--------|--------------|
| 1 Preflight | `scripts/preflight.sh` | Checks OS, CPU, RAM, disk, DNS, internet |
| 2 Java | `scripts/install_java.sh` | Installs OpenJDK 17 and sets JAVA_HOME |
| 3 Tomcat | `scripts/install_tomcat.sh` | Tomcat as user `tomcat`, systemd service, port 8080 |
| 4 Database | `scripts/install_database.sh` | Oracle AI Database 26ai Free, listener on 1521 |
| 5 APEX | `scripts/install_apex_db.sh` | Installs APEX in FREEPDB1, creates ADMIN |
| 6 ORDS | `scripts/install_ords.sh` | Installs ORDS, deploys it on Tomcat |
| 7 Proxy | `scripts/install_proxy.sh` | Apache on port 80 forwards to Tomcat |
| 8 Validation | `scripts/validate.sh` | 18 PASS or FAIL checks |

Every stage checks if its work is already done and skips it, so the installer can be run again safely.
## Architecture

- Only port 80 (and 22 for SSH) is needed from outside.
- Apache forwards `/ords` and `/i` (APEX images) to Tomcat.
- ORDS talks to the database on the same server. Port 1521 is not open in the firewall.

## Security design

- SELinux stays **Enforcing**. The only change is the switch `httpd_can_network_connect`, so Apache may call Tomcat.
- Tomcat runs as the dedicated user `tomcat`. Apache workers run as `apache`. Nothing runs as root except opening port 80.
- Passwords are typed hidden at runtime. They are never stored in config files or logs. SQL goes through stdin, so passwords do not appear in the process list.
- ORDS keeps its database passwords encrypted in a wallet inside `/etc/ords`, which only `tomcat` can enter (mode 750).
- Firewall: `ssh`, `http` and optionally `8080/tcp`. Port 1521 is closed.

## Logs

Logs are written to `/var/log/oracle-apex-installer/` (one main log per day and one log per stage).

## Testing

Run the final check at any time:

```bash
sudo ./scripts/validate.sh
```

It prints PASS or FAIL for Java, database, listener, APEX, Tomcat, ORDS, Apache, firewall, SELinux and auto-start after reboot. See `docs/troubleshooting.md` for common problems.
