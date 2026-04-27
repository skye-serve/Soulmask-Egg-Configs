#!/bin/bash

LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"

# Kill any other tracker processes that might be hanging around
pkill -f tracker.sh

# Fresh start
rm -f "$MSG_ID_FILE"
echo "" > "$LIST_FILE"
echo "--- Tracker Nuclear Reset Started $(date) ---" > tracker_debug.log

if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="${SERVER_MAP:-Cloud Mist Forest}"
fi

# --- Background Listener ---
tail -F -n 0 "$LOG_FILE" 2>/dev/null | while read -r line; do
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"' | tr -d "'")
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

# --- Main Update Loop ---
while true; do
    players_online=$(grep -c . "$LIST_FILE" || echo "0")
    FINAL_LIST=$(paste -sd ", " "$LIST_FILE")
    [ -z "$FINAL_LIST" ] && FINAL_LIST="None online"
    CLEAN_SERVER_NAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"')

    JSON_PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "🎮 Soulmask Live Server Status",
    "color": 5763719,
    "fields": [
      {"name": "Server Name", "value": "${CLEAN_SERVER_NAME}", "inline": false},
      {"name": "Status", "value": "🟢 Online", "inline": true},
      {"name": "Map", "value": "${DISPLAY_MAP}", "inline": true},
      {"name": "Current Players", "value": "${players_online}", "inline": true},
      {"name": "Online Players", "value": "\`\`\`${FINAL_LIST}\`\`\`", "inline": false}
    ],
    "footer": {"text": "Last Updated: $(date +'%T') | Skye Serve"}
  }]
}
EOF
)

    if [ ! -s "$MSG_ID_FILE" ]; then
        # INITIAL POST
        echo "[STEP 1] Attempting to send initial message..." >> tracker_debug.log
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}?wait=true")
        
        # Robust ID extraction using sed
        NEW_ID=$(echo "$RESPONSE" | sed -n 's/.*"id": "\([0-9]*\)".*/\1/p')
        
        if [[ "$NEW_ID" =~ ^[0-9]+$ ]]; then
            echo "$NEW_ID" > "$MSG_ID_FILE"
            echo "[STEP 2] Success! Message ID: $NEW_ID" >> tracker_debug.log
        else
            echo "[ERROR] Discord rejection: $RESPONSE" >> tracker_debug.log
        fi
    else
        # PERIODIC UPDATE
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}")
        
        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "204" ]; then
            echo "[ERROR] Patch failed (HTTP $HTTP_CODE). Retrying fresh message..." >> tracker_debug.log
            rm -f "$MSG_ID_FILE"
        else
            echo "[SUCCESS] Board updated at $(date +'%T')" >> tracker_debug.log
        fi
    fi

    sleep 10
done
