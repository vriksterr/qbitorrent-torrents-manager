#!/usr/bin/env bash
# -------------------------------------
# qBittorrent 24/7 Upload Monitor + Cleanup Script (fixed for Alpine / Docker)
# -------------------------------------

# ---- Configuration ----
QBIT_HOST="http://localhost:20022"
USERNAME=""
PASSWORD=""

CHECK_INTERVAL=2                # check every N seconds
UPLOAD_THRESHOLD_KBPS=300       # avg upload limit (KB/s)
TIME_THRESHOLD_SEC=$((6*60*60)) # 2 hours in seconds
STATE_FILE="/tmp/qbt_upload_tracker.json"
COOKIE_JAR="/tmp/qbt_cookie.txt"

# ---- Function to get delete behavior per category ----
get_delete_behavior() {
    local category="$1"
    case "$category" in
        movies) echo true ;;   # delete torrent + files
        series) echo true ;;   # delete torrent + files
        games) echo false ;;   # delete torrent only
        *) echo false ;;       # default behavior
    esac
}

# ---- Ensure jq & curl ----
if ! command -v jq &>/dev/null; then
    echo "[*] Installing jq..."
    apk add --no-cache jq curl >/dev/null 2>&1
fi

# ---- Login Function ----
login() {
    echo "[*] Logging into qBittorrent..."
    LOGIN_RESPONSE=$(curl -s -c "$COOKIE_JAR" \
        -d "username=$USERNAME" \
        -d "password=$PASSWORD" \
        "$QBIT_HOST/api/v2/auth/login")

    if [[ "$LOGIN_RESPONSE" != "Ok." ]]; then
        echo "[!] Login failed. Response: $LOGIN_RESPONSE"
        echo "[!] Retrying in 30s..."
        sleep 30
        login
    else
        echo "[+] Logged in successfully"
    fi
}

# ---- API Fetch ----
get_torrents() {
    curl -s -b "$COOKIE_JAR" "$QBIT_HOST/api/v2/torrents/info"
}

# ---- Delete torrent ----
delete_torrent() {
    local HASH="$1"
    local NAME="$2"
    local DELETE_FILES="$3" # true/false
    echo "[-] Deleting torrent: $NAME ($HASH) | delete_files=$DELETE_FILES"
    curl -s -b "$COOKIE_JAR" -d "hashes=$HASH" \
         -d "deleteFiles=$DELETE_FILES" \
         "$QBIT_HOST/api/v2/torrents/delete" >/dev/null
}

# ---- Main Monitor ----
monitor_uploads() {
    [[ ! -f "$STATE_FILE" ]] && echo "{}" > "$STATE_FILE"
    TORRENTS=$(get_torrents)
    echo "{}" > /tmp/qbt_new_state.json

    echo "$TORRENTS" | jq -c '.[]' | while read -r torrent; do
        CATEGORY=$(echo "$torrent" | jq -r '.category' | tr '[:upper:]' '[:lower:]')
        STATE=$(echo "$torrent" | jq -r '.state')
        HASH=$(echo "$torrent" | jq -r '.hash')
        NAME=$(echo "$torrent" | jq -r '.name')
        UP_SPEED=$(echo "$torrent" | jq -r '.upspeed')
        PRIVATE=$(echo "$torrent" | jq -r '.private')
        FORCE_START=$(echo "$torrent" | jq -r '.force_start')

        # ---- Filter rules ----
        if [[ "$CATEGORY" != "movies" && "$CATEGORY" != "series" && "$CATEGORY" != "games" ]]; then
            continue
        fi

        # ---- Ignore private torrents ----
        if [[ "$PRIVATE" == "true" || "$PRIVATE" == "1" ]]; then
            echo "[skip] $NAME ? private torrent"
            continue
        fi

        # ---- Ignore force-started torrents ----
        if [[ "$FORCE_START" == "true" || "$FORCE_START" == "1" ]]; then
            echo "[skip] $NAME ? forced upload/seeding"
            continue
        fi

        # ---- Ignore unwanted states ----
        STATE_LOWER=$(echo "$STATE" | tr '[:upper:]' '[:lower:]')
        if [[ "$STATE_LOWER" != "uploading" && "$STATE_LOWER" != "stalledup" ]]; then
            continue
        fi

        # ---- Speed Tracking ----
        SPEED_KBPS=$((UP_SPEED / 1024))
        PREV_ENTRY=$(jq -r --arg h "$HASH" '.[$h]' "$STATE_FILE")
        PREV_AVG=$(echo "$PREV_ENTRY" | jq -r '.avg_speed // 0')
        PREV_TIME=$(echo "$PREV_ENTRY" | jq -r '.low_speed_time // 0')

        if (( SPEED_KBPS < UPLOAD_THRESHOLD_KBPS )); then
            LOW_SPEED_TIME=$((PREV_TIME + CHECK_INTERVAL))
        else
            LOW_SPEED_TIME=0
        fi

        NEW_AVG=$(((PREV_AVG + SPEED_KBPS) / 2))

        # ---- Action ----
        if (( LOW_SPEED_TIME >= TIME_THRESHOLD_SEC )); then
            DELETE_FILES=$(get_delete_behavior "$CATEGORY")
            echo "[!] Torrent '$NAME' <$UPLOAD_THRESHOLD_KBPS KB/s for 2h ? removing | delete_files=$DELETE_FILES"
            delete_torrent "$HASH" "$NAME" "$DELETE_FILES"
            continue
        fi

        # ---- Save updated entry ----
        jq --arg h "$HASH" \
           --argjson avg "$NEW_AVG" \
           --argjson time "$LOW_SPEED_TIME" \
           '. + {($h): {"avg_speed": $avg, "low_speed_time": $time}}' \
           /tmp/qbt_new_state.json > /tmp/qbt_tmp.json && mv /tmp/qbt_tmp.json /tmp/qbt_new_state.json
    done

    # ---- Replace old state ----
    mv /tmp/qbt_new_state.json "$STATE_FILE"
}

# ---- Main Loop ----
main_loop() {
    login
    echo "[*] Monitoring torrents 24/7..."
    while true; do
        echo "--------------------------------------"
        echo "[*] Checking at $(date)"
        monitor_uploads

        # Re-login if cookie expired
        if ! curl -s -b "$COOKIE_JAR" "$QBIT_HOST/api/v2/app/version" | grep -q '[0-9]'; then
            echo "[!] Session expired, re-logging..."
            login
        fi

        echo "[*] Sleeping for $CHECK_INTERVAL seconds..."
        sleep "$CHECK_INTERVAL"
    done
}

main_loop
