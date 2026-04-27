#!/bin/bash

# Configuration
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"

# Clean up on fresh boot
rm -f "$MSG_ID_FILE"
echo "" > "$LIST_FILE"
echo "--- Tracker Started $(date) ---" > tracker_debug.log

# Map Name Translation
if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="${SERVER_MAP:-Unknown Realm}"
fi

# --- Background Listener ---
tail -F -n 0 "$LOG_FILE" 2>/dev/null | while read -r line; do
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"' | tr -d "'")
        if ! grep -q "^$NAME$" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
            echo "[LOG] Player Joined: $NAME" >> tracker_debug.log
        fi
    fi

    if [[ "$line" == *"logged out"* ]] || [[ "$line" == *"ClosePort"* ]]; then
        while read -r p_name; do
            if [[ "$line" == *"$p_name"* ]]; then
                sed -i "/^$p_name$/d" "$LIST_FILE"
                echo "[LOG] Player Left: $p_name" >> tracker_debug.log
            fi
        done < "$LIST_FILE"
    fi
done &

# --- Main Discord Update Loop ---
while true; do
    players_online=$(grep -c . "$LIST_FILE" || echo "0")
    FINAL_LIST=$(paste -sd ", " "$LIST_FILE")
    [ -z "$FINAL_LIST" ] && FINAL_LIST="None online"

    # Escape quotes in Server Name for JSON safety
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
        # TRY TO POST NEW MESSAGE
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}?wait=true")
        
        # Only save the ID if it actually looks like a Snowflake ID (numbers only)
        NEW_ID=$(echo "$RESPONSE" | grep -oP '"id": "\K[0-9]+')
        
        if [ -n "$NEW_ID" ]; then
            echo "$NEW_ID" > "$MSG_ID_FILE"
            echo "[DISCORD] Successfully created new status board: $NEW_ID" >> tracker_debug.log
        else
            echo "[ERROR] Discord rejected the message! Response: $RESPONSE" >> tracker_debug.log
        fi
    else
        # EDIT EXISTING MESSAGE
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}")
        
        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "204" ]; then
            echo "[ERROR] Update failed (HTTP $HTTP_CODE). Clearing ID to try a fresh message..." >> tracker_debug.log
            rm -f "$MSG_ID_FILE"
        else
            echo "[DEBUG] Updated board at $(date +'%T')" >> tracker_debug.log
        fi
    fi

    sleep 10
done
