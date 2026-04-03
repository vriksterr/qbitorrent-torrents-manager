#!/usr/bin/env bash

QBIT_HOST="http://localhost:20022"
USERNAME=""
PASSWORD=""

CHECK_INTERVAL=2		# seconds
UPLOAD_THRESHOLD_KBPS=100	# KB/s
TIME_THRESHOLD_SEC=$((2*60*60))	# 6 hours

STATE_FILE="/tmp/qbt_upload_tracker.json"
COOKIE_JAR="/tmp/qbt_cookie.txt"

get_delete_behavior() {
    case "$1" in
        movies|series) echo true ;;
        games)         echo false ;;
        *)             echo false ;;
    esac
}

# ---- Ensure dependencies ----
command -v jq >/dev/null || apk add --no-cache jq curl >/dev/null 2>&1

# ---- Login (SAFE LOOP) ----
login() {
    echo "[*] Waiting for qBittorrent API..."

    # Wait until API is reachable
    while ! curl -s "$QBIT_HOST/api/v2/app/version" | grep -q '[0-9]'; do
        sleep 2
    done

    echo "[*] Logging into qBittorrent..."

    while true; do
        RESPONSE=$(curl -s -c "$COOKIE_JAR" \
            -d "username=$USERNAME" \
            -d "password=$PASSWORD" \
            "$QBIT_HOST/api/v2/auth/login")

        if [[ "$RESPONSE" == "Ok." ]]; then
            echo "[+] Logged in"
            return
        fi

        echo "[!] Login failed, retrying..."
        sleep 2
    done
}

# ---- API SAFE FETCH ----
get_torrents() {
    RESPONSE=$(curl -s -b "$COOKIE_JAR" "$QBIT_HOST/api/v2/torrents/info")

    # Validate JSON
    if echo "$RESPONSE" | jq empty >/dev/null 2>&1; then
        echo "$RESPONSE"
        return 0
    else
        return 1
    fi
}

delete_torrent() {
    local HASH="$1"
    local NAME="$2"
    local DELETE_FILES="$3"

    echo "[-] Deleting: $NAME | delete_files=$DELETE_FILES"
    curl -s -b "$COOKIE_JAR" \
        -d "hashes=$HASH" \
        -d "deleteFiles=$DELETE_FILES" \
        "$QBIT_HOST/api/v2/torrents/delete" >/dev/null
}

monitor_uploads() {
    [[ ! -f "$STATE_FILE" ]] && echo "{}" > "$STATE_FILE"
    echo "{}" > /tmp/qbt_new_state.json

    TORRENTS=$(get_torrents) || {
        echo "[!] API not ready / invalid response"
        return 1
    }

    echo "$TORRENTS" | jq -c '.[]' | while read -r torrent; do
        CATEGORY=$(jq -r '.category' <<<"$torrent" | tr '[:upper:]' '[:lower:]')
        STATE=$(jq -r '.state' <<<"$torrent" | tr '[:upper:]' '[:lower:]')
        HASH=$(jq -r '.hash' <<<"$torrent")
        NAME=$(jq -r '.name' <<<"$torrent")
        UP_SPEED=$(jq -r '.upspeed' <<<"$torrent")
        PRIVATE=$(jq -r '.private' <<<"$torrent")
        FORCE=$(jq -r '.force_start' <<<"$torrent")

        [[ ! "$CATEGORY" =~ ^(movies|series|games)$ ]] && continue
        [[ "$PRIVATE" == "true" || "$PRIVATE" == "1" ]] && continue
        [[ "$FORCE" == "true" || "$FORCE" == "1" ]] && continue
        [[ ! "$STATE" =~ ^(uploading|stalledup)$ ]] && continue

        PREV=$(jq -r --arg h "$HASH" '.[$h] // {}' "$STATE_FILE")
        PREV_BYTES=$(jq -r '.bytes_uploaded // 0' <<<"$PREV")
        PREV_TIME=$(jq -r '.time_sec // 0' <<<"$PREV")
        PREV_LOW=$(jq -r '.low_speed_time // 0' <<<"$PREV")

        BYTES_THIS_INTERVAL=$((UP_SPEED * CHECK_INTERVAL))
        TOTAL_BYTES=$((PREV_BYTES + BYTES_THIS_INTERVAL))
        TOTAL_TIME=$((PREV_TIME + CHECK_INTERVAL))

        SPEED_KBPS=$((UP_SPEED / 1024))

        if (( SPEED_KBPS < UPLOAD_THRESHOLD_KBPS )); then
            LOW_SPEED_TIME=$((PREV_LOW + CHECK_INTERVAL))
        else
            LOW_SPEED_TIME=0
        fi

        AVG_KBPS=0
        if (( TOTAL_TIME > 0 )); then
            AVG_KBPS=$(( (TOTAL_BYTES / TOTAL_TIME) / 1024 ))
        fi

        if (( LOW_SPEED_TIME >= TIME_THRESHOLD_SEC && AVG_KBPS < UPLOAD_THRESHOLD_KBPS )); then
            DELETE_FILES=$(get_delete_behavior "$CATEGORY")
            echo "[!] Removing '$NAME' | avg=${AVG_KBPS}KB/s | low-speed 2h"
            delete_torrent "$HASH" "$NAME" "$DELETE_FILES"
            continue
        fi

        jq --arg h "$HASH" \
           --argjson b "$TOTAL_BYTES" \
           --argjson t "$TOTAL_TIME" \
           --argjson l "$LOW_SPEED_TIME" \
           '. + {($h): {"bytes_uploaded": $b, "time_sec": $t, "low_speed_time": $l}}' \
           /tmp/qbt_new_state.json > /tmp/qbt_tmp.json && mv /tmp/qbt_tmp.json /tmp/qbt_new_state.json
    done

    mv /tmp/qbt_new_state.json "$STATE_FILE"
}

main() {
    login
    echo "[*] Monitoring torrents..."

    while true; do
        echo "--------------------------------------"
        echo "[*] Check @ $(date)"

        if ! monitor_uploads; then
            echo "[!] Reconnecting..."
            login
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main
