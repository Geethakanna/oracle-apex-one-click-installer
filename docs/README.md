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
