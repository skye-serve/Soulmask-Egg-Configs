#!/bin/bash

LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"

# Kill old versions
pkill -f tracker.sh

# Fresh start
rm -f "$MSG_ID_FILE"
echo "" > "$LIST_FILE"
echo "--- Pro Tracker Final Fix: $(date) ---" > tracker_debug.log

# Map Name Translation
if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="Cloud Mist Forest"
fi

# --- Background Listener ---
tail -F -n 0 "$LOG_FILE" 2>/dev/null | while read -r line; do
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -dc '[:print:]' | tr -d '"' | tr -d "'")
        if ! grep -q "^$NAME$" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
        fi
    fi
    if [[ "$line" == *"logged out"* ]] || [[ "$line" == *"ClosePort"* ]]; then
        while read -r p_name; do
            if [[ "$line" == *"$p_name"* ]]; then
                sed -i "/^$p_name$/d" "$LIST_FILE"
            fi
        done < "$LIST_FILE"
    fi
done &

# --- Safe JSON Builder ---
build_json() {
    local s_name="$1"
    local map="$2"
    local count="$3"
    local list="$4"
    local time="$5"

    cat <<EOF
{
  "embeds": [{
    "title": "🎮 Soulmask Live Server Status",
    "color": 5763719,
    "fields": [
      {"name": "Server Name", "value": "$s_name", "inline": false},
      {"name": "Status", "value": "🟢 Online", "inline": true},
      {"name": "Map", "value": "$map", "inline": true},
      {"name": "Current Players", "value": "$count", "inline": true},
      {"name": "Online Players", "value": "\`\`\`$list\`\`\`", "inline": false}
    ],
    "footer": {"text": "Last Updated: $time | Skye Serve"}
  }]
}
EOF
}

# --- Main Update Loop ---
while true; do
    CLEAN_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')
    CLEAN_MAP=$(echo "$DISPLAY_MAP" | tr -d '"')
    PLAYERS=$(grep -c "[^[:space:]]" "$LIST_FILE" || echo "0")
    CLEAN_LIST=$(paste -sd ", " "$LIST_FILE" | tr -d '"' | tr -dc '[:print:]' | sed 's/^, //')
    [ -z "$CLEAN_LIST" ] && CLEAN_LIST="None online"
    CUR_TIME=$(date +'%T')

    build_json "$CLEAN_SNAME" "$CLEAN_MAP" "$PLAYERS" "$CLEAN_LIST" "$CUR_TIME" > payload.json

    if [ ! -s "$MSG_ID_FILE" ]; then
        # INITIAL SEND
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d @payload.json "${DISCORD_WEBHOOK}?wait=true")
        
        # FIXED: Removed the space after "id": to match Discord's actual response
        NEW_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":"\([0-9]*\)".*/\1/p')
        
        if [[ "$NEW_ID" =~ ^[0-9]+$ ]]; then
            echo "$NEW_ID" > "$MSG_ID_FILE"
            echo "[SUCCESS] Created Message: $NEW_ID" >> tracker_debug.log
        else
            echo "[ERROR] Could not parse ID from: $RESPONSE" >> tracker_debug.log
        fi
    else
        # EDIT
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" -d @payload.json "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}")
        
        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "204" ]; then
            echo "[RETRY] HTTP $HTTP_CODE - Resetting ID" >> tracker_debug.log
            rm -f "$MSG_ID_FILE"
        else
            echo "[OK] Updated $CUR_TIME" >> tracker_debug.log
        fi
    fi

    sleep 10
done
