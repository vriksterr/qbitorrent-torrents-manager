#!/bin/bash
# -------------------------------------
# qBittorrent 24/7 Auto Cleanup Script
# -------------------------------------

# --- Config ---
QBIT_HOST="http://localhost:20022"      # Must match the address you use in a browser AND qBittorrent's WebUI "Referer"/Host check
USERNAME=""
PASSWORD=""
DELETE_FILES=true                       # Set to false if you want to keep the files
CHECK_INTERVAL=5                        # Time in seconds between checks
BAD_EXTS=("iso" "exe" "scr" "rar" "arj") # File types to delete
COOKIE_JAR="/tmp/qb_cookie.txt"
DEBUG=true                              # Set to false once everything is confirmed working
MAX_LOGIN_RETRIES=5

# --- Ensure jq is installed ---
if ! command -v jq &>/dev/null; then
  echo "[*] jq not found, attempting to install..."
  if command -v apk &>/dev/null; then
    apk add --no-cache jq
  elif command -v apt-get &>/dev/null; then
    apt-get update && apt-get install -y jq
  else
    echo "[!] Could not auto-install jq (unknown package manager). Please install it manually."
    exit 1
  fi
fi

if ! command -v jq &>/dev/null; then
  echo "[!] jq still not available after install attempt. Exiting."
  exit 1
fi

debug() {
  if [[ "$DEBUG" == true ]]; then
    echo "[DEBUG] $*"
  fi
}

# --- Login Function ---
login() {
  local attempt=0
  while (( attempt < MAX_LOGIN_RETRIES )); do
    ((attempt++))
    debug "Login attempt $attempt of $MAX_LOGIN_RETRIES against $QBIT_HOST"

    # -D - dumps headers to stdout along with body, -w adds the HTTP status code on its own line
    local RAW
    RAW=$(curl -s -D - -o /tmp/qb_login_body.txt -c "$COOKIE_JAR" \
      -H "Referer: $QBIT_HOST" \
      -H "Origin: $QBIT_HOST" \
      --data-urlencode "username=$USERNAME" \
      --data-urlencode "password=$PASSWORD" \
      -w "HTTP_STATUS:%{http_code}" \
      "$QBIT_HOST/api/v2/auth/login")

    local STATUS
    STATUS=$(echo "$RAW" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
    local BODY
    BODY=$(cat /tmp/qb_login_body.txt)

    debug "HTTP status: $STATUS"
    debug "Response body: $BODY"
    debug "Response headers:"
    if [[ "$DEBUG" == true ]]; then
      echo "$RAW" | sed '/HTTP_STATUS:/d'
    fi

    # qBittorrent <5.2.0 returns HTTP 200 with body "Ok." on success.
    # qBittorrent >=5.2.0 changed this to HTTP 204 with an empty body on success
    # (see qbittorrent/qBittorrent#23270). Accept either as a valid login.
    if [[ ( "$STATUS" == "200" && "$BODY" == "Ok." ) || "$STATUS" == "204" ]]; then
      echo "[+] Logged in successfully"
      return 0
    fi

    if [[ "$STATUS" == "403" ]]; then
      echo "[!] Got HTTP 403. This is almost always a Referer/Origin or Host-header"
      echo "    mismatch, or qBittorrent's brute-force ban kicking in after failed attempts."
      echo "    -> In qBittorrent: Settings > WebUI, check 'Host header validation' and"
      echo "       make sure QBIT_HOST in this script matches what's configured there."
    elif [[ "$BODY" == "Fails." ]]; then
      echo "[!] Login rejected: wrong username/password."
    else
      echo "[!] Unexpected response (status=$STATUS body='$BODY'). Is QBIT_HOST reachable"
      echo "    from where this script runs (not just from your browser)?"
    fi

    echo "[!] Login failed. Retrying in 5s... ($attempt/$MAX_LOGIN_RETRIES)"
    sleep 5
  done

  echo "[!] Exceeded $MAX_LOGIN_RETRIES login attempts. Giving up to avoid triggering an IP ban."
  exit 1
}

# --- Fetch Torrents ---
get_torrents() {
  curl -s -b "$COOKIE_JAR" -H "Referer: $QBIT_HOST" "$QBIT_HOST/api/v2/torrents/info"
}

# --- Fetch Files for a Torrent ---
get_torrent_files() {
  local HASH="$1"
  curl -s -b "$COOKIE_JAR" -H "Referer: $QBIT_HOST" "$QBIT_HOST/api/v2/torrents/files?hash=$HASH"
}

# --- Delete Torrent ---
delete_torrent() {
  local HASH="$1"
  local NAME="$2"
  echo "[-] Deleting torrent: $NAME ($HASH)"
  curl -s -b "$COOKIE_JAR" -H "Referer: $QBIT_HOST" \
       -d "hashes=$HASH" \
       -d "deleteFiles=$DELETE_FILES" \
       "$QBIT_HOST/api/v2/torrents/delete" >/dev/null
}

# --- Main Cleanup Logic ---
cleanup_check() {
  local TORRENTS
  TORRENTS=$(get_torrents)

  if [[ -z "$TORRENTS" ]] || ! echo "$TORRENTS" | jq -e . &>/dev/null; then
    echo "[!] Could not parse torrent list (session may have expired). Re-logging in..."
    login
    return
  fi

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
