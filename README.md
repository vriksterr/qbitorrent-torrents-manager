# 🧹 qBittorrent 24/7 Auto Cleanup Script

![Bash](https://img.shields.io/badge/Language-Bash-blue)
![License](https://img.shields.io/badge/License-MIT-green)

A **Bash script** that continuously monitors qBittorrent torrents in the categories `series` and `movies`, and automatically deletes any torrent that contains **.iso, .exe, or .scr** files. Ideal for keeping your torrent library clean and safe.

---

## 🚀 Features

* Runs 24/7 to monitor torrents
* Automatically deletes unsafe files (`.iso`, `.exe`, `.scr`)
* Optionally deletes torrent **and/or data files**
* Configurable check interval
* Works with **qBittorrent WebUI (v2 API)**
* Easy to run manually, via `nohup`, or as a **systemd service**

---

## 📝 Requirements

* **qBittorrent** with WebUI enabled
* **jq** installed for JSON parsing
* Bash shell (Linux/macOS)
* cURL installed

---

## ⚙️ Installation

1. **Clone or download the script**:

```bash
git clone https://github.com/vriksterr/qbitorrent-monitor-delete
cd qbitorrent-monitor-delete
sudo nano /usr/local/bin/qbitorrent-monitor-delete.sh
```

2. **Paste the script** and save.

3. **Make it executable**:

```bash
sudo chmod +x /usr/local/bin/qbitorrent-monitor-delete.sh
```

4. **Install jq** if not installed:

```bash
sudo apt install jq -y   # Debian/Ubuntu
sudo yum install jq -y   # CentOS/RHEL
sudo pacman -S jq        # Arch Linux
```

---

## 🔧 Configuration

Edit the script to update:

```bash
QBIT_HOST="http://<qbittorrent-host>:<port>"
USERNAME="your_username"
PASSWORD="your_password"
DELETE_FILES=true         # true = delete files, false = keep files
CHECK_INTERVAL=60         # seconds between checks
BAD_EXTS=("iso" "exe" "scr")  # file types to remove
```

---

## 🏃 Usage

### Run manually:

```bash
/usr/local/bin/auto_remove_bad_torrents.sh
```

### Run in the background (24/7):

```bash
nohup /usr/local/bin/qbitorrent-monitor-delete.sh > /var/log/qb_cleanup.log 2>&1 &
```

* Logs are written to `/var/log/qb_cleanup.log`
* To follow logs:

```bash
tail -f /var/log/qb_cleanup.log
```

---

## ⚡ Optional: Run at Startup with systemd

1. Create a service file:

```bash
sudo nano /etc/systemd/system/qb_cleanup.service
```

2. Paste:

```ini
[Unit]
Description=qBittorrent Auto Cleanup Script
After=network.target

[Service]
ExecStart=/usr/local/bin/qbitorrent-monitor-delete.sh
Restart=always
User=<your-username>
StandardOutput=file:/var/log/qb_cleanup.log
StandardError=file:/var/log/qb_cleanup.log

[Install]
WantedBy=multi-user.target
```

3. Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable qb_cleanup
sudo systemctl start qb_cleanup
```

---

## ⚠️ Notes

* Safe mode: set `DELETE_FILES=false` to only remove torrents without deleting the files.
* You can adjust the `BAD_EXTS` array to include any other unsafe file types.
* Ensure your qBittorrent WebUI credentials are correct.

---

## 📝 License

MIT License – free to use and modify. No warranty provided.

---

If you want, I can also create a **ready-to-push GitHub repo structure** with:

* `README.md`
* `auto_remove_bad_torrents.sh`
* `.gitignore` for logs

Do you want me to do that?
