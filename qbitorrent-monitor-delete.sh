#!/bin/bash
# -------------------------------------
# qBittorrent 24/7 Auto Cleanup Script
# -------------------------------------

QBIT_HOST="http://<ip>:<port>"
USERNAME="username"
PASSWORD="password"
DELETE_FILES=true          # Set to false if you want to keep the files
CHECK_INTERVAL=60          # Time in seconds between checks
BAD_EXTS=("iso" "exe" "scr")
COOKIE_JAR="/tmp/qb_cookie.txt"

# Ensure jq is installed
if ! command -v jq &>/dev/null; then
  echo "[!] Please install jq: sudo apt install jq -y"
  exit 1
fi

# --- Login Function ---
login() {
  LOGIN_RESPONSE=$(curl -s -c "$COOKIE_JAR" \
    -d "username=$USERNAME" \
    -d "password=$PASSWORD" \
    "$QBIT_HOST/api/v2/auth/login")

  if [[ "$LOGIN_RESPONSE" != "Ok." ]]; then
    echo "[!] Login failed. Retrying in 30s..."
    sleep 30
    login
  else
    echo "[+] Logged in successfully"
  fi
}

# --- Fetch Torrents ---
get_torrents() {
  curl -s -b "$COOKIE_JAR" "$QBIT_HOST/api/v2/torrents/info"
}

# --- Fetch Files for a Torrent ---
get_torrent_files() {
  local HASH="$1"
  curl -s -b "$COOKIE_JAR" "$QBIT_HOST/api/v2/torrents/files?hash=$HASH"
}

# --- Delete Torrent ---
delete_torrent() {
  local HASH="$1"
  local NAME="$2"
  echo "[-] Deleting torrent: $NAME ($HASH)"
  curl -s -b "$COOKIE_JAR" -d "hashes=$HASH" \
       -d "deleteFiles=$DELETE_FILES" \
       "$QBIT_HOST/api/v2/torrents/delete" >/dev/null
}

# --- Main Cleanup Logic ---
cleanup_check() {
  TORRENTS=$(get_torrents)

  echo "$TORRENTS" | jq -c '.[]' | while read -r torrent; do
    CATEGORY=$(echo "$torrent" | jq -r '.category' | tr '[:upper:]' '[:lower:]')
    HASH=$(echo "$torrent" | jq -r '.hash')
    NAME=$(echo "$torrent" | jq -r '.name')

    if [[ "$CATEGORY" == "series" || "$CATEGORY" == "movies" ]]; then
      FILES=$(get_torrent_files "$HASH")
      for ext in "${BAD_EXTS[@]}"; do
        if echo "$FILES" | grep -qiE "\.${ext}\""; then
          echo "[!] Found bad file in '$NAME' ($CATEGORY): *.$ext"
          delete_torrent "$HASH" "$NAME"
          break
        fi
      done
    fi
  done
}

# --- Main Loop ---
main_loop() {
  login
  echo "[*] Starting continuous torrent check every $CHECK_INTERVAL seconds..."
  while true; do
    echo "--------------------------------------"
    echo "[*] Checking for bad files at $(date)"
    cleanup_check
    echo "[*] Sleeping for $CHECK_INTERVAL seconds..."
    sleep "$CHECK_INTERVAL"
  done
}

main_loop
