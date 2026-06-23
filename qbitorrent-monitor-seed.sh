#!/usr/bin/env bash
# -------------------------------------
# qBittorrent Average Monitor + Delete ETA
# -------------------------------------

QBIT_HOST="http://localhost:20022"
USERNAME=""
PASSWORD=""

CHECK_INTERVAL=1
UPLOAD_THRESHOLD_KBPS=100
TIME_THRESHOLD_SEC=$((72*60*60))  
STATE_FILE="/tmp/qbt_avg_tracker.json"
COOKIE_JAR="/tmp/qbt_cookie.txt"

ALPHA=$(awk "BEGIN {print 2/(($TIME_THRESHOLD_SEC/$CHECK_INTERVAL)+1)}")

[[ ! -f "$STATE_FILE" ]] && echo "{}" > "$STATE_FILE"

login() {
    curl -s -c "$COOKIE_JAR" -d "username=$USERNAME" -d "password=$PASSWORD" "$QBIT_HOST/api/v2/auth/login" > /dev/null
}

monitor() {
    local RAW_DATA=$(curl -s -b "$COOKIE_JAR" "$QBIT_HOST/api/v2/torrents/info")
    
    if ! echo "$RAW_DATA" | jq empty 2>/dev/null; then
        login
        return
    fi

    local TMP_STATE=$(mktemp)
    echo "{}" > "$TMP_STATE"
    local NOW=$(date +%s)

    local HASHES=$(echo "$RAW_DATA" | jq -r '.[] | 
        select(.category | ascii_downcase | test("movies|series")) | 
        select(.private == false and .force_start == false) | 
        select(.progress == 1) | 
        select(.tags == "") | 
        select(.state | ascii_downcase | test("uploading|stalledup|forcedup")) | 
        .hash')

    echo "--- Public Seeding Monitor ($(date +%H:%M:%S)) ---"

    for HASH in $HASHES; do
        local ITEM=$(echo "$RAW_DATA" | jq -c ".[] | select(.hash == \"$HASH\")")
        local NAME=$(echo "$ITEM" | jq -r '.name')
        local CUR_SPEED=$(( $(echo "$ITEM" | jq -r '.upspeed') / 1024 ))
        local CAT=$(echo "$ITEM" | jq -r '.category | ascii_downcase')
        
        local STATS=$(jq -r --arg h "$HASH" '.[$h] // {"avg_speed": -1, "first_seen": 0}' "$STATE_FILE")
        local PREV_AVG=$(echo "$STATS" | jq -r '.avg_speed')
        local FIRST_SEEN=$(echo "$STATS" | jq -r '.first_seen')

        local NEW_AVG
        if [[ "$PREV_AVG" == "-1" ]]; then
            NEW_AVG=$CUR_SPEED
            FIRST_SEEN=$NOW
        else
            NEW_AVG=$(awk "BEGIN {print ($ALPHA * $CUR_SPEED) + ((1 - $ALPHA) * $PREV_AVG)}")
        fi

        local TRACKING_DURATION=$(( NOW - FIRST_SEEN ))
        local STATUS_STR=""

        if (( TRACKING_DURATION > TIME_THRESHOLD_SEC )); then
            if (( $(awk "BEGIN {print ($NEW_AVG < $UPLOAD_THRESHOLD_KBPS)}") )); then
                local DEL_FILES="false"
                [[ "$CAT" =~ ^(movies|series)$ ]] && DEL_FILES="true"
                echo "[!!!] REMOVING: $NAME"
                curl -s -b "$COOKIE_JAR" -d "hashes=$HASH" -d "deleteFiles=$DEL_FILES" "$QBIT_HOST/api/v2/torrents/delete"
                continue
            fi
            
            # Calculate ETA (How long until Average drops to threshold if current speed stays same)
            if (( CUR_SPEED < UPLOAD_THRESHOLD_KBPS )); then
                # Math: Steps = log((Threshold - Speed)/(Avg - Speed)) / log(1 - Alpha)
                # Simplified linear approximation for shell:
                ETA_MINS=$(awk "BEGIN { 
                    if ($NEW_AVG > $UPLOAD_THRESHOLD_KBPS) {
                        mins = (log(($UPLOAD_THRESHOLD_KBPS - $CUR_SPEED)/($NEW_AVG - $CUR_SPEED)) / log(1 - $ALPHA)) * ($CHECK_INTERVAL / 60);
                        printf \"%dm\", mins
                    } else { printf \"0m\" }
                }")
                STATUS_STR="[DEL IN ${ETA_MINS}]"
            else
                STATUS_STR="[SAFE]"
            fi
        else
            REMAINING=$(( (TIME_THRESHOLD_SEC - TRACKING_DURATION) / 60 ))
            STATUS_STR="[WARM ${REMAINING}m]"
        fi

        printf "%-15s %-40.40s | Avg: %7.1f KB/s | Cur: %4d KB/s\n" "$STATUS_STR" "$NAME" "$NEW_AVG" "$CUR_SPEED"

        local UPDATED_STATE=$(jq --arg h "$HASH" --argjson a "$NEW_AVG" --argjson f "$FIRST_SEEN" \
            '. + {($h): {"avg_speed": $a, "first_seen": $f}}' "$TMP_STATE")
        echo "$UPDATED_STATE" > "$TMP_STATE"
    done

    mv "$TMP_STATE" "$STATE_FILE"
}

login
while true; do
    monitor
    sleep "$CHECK_INTERVAL"
done
