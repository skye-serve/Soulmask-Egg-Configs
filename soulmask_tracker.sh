#!/bin/bash

# Configuration
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"

# Clean up files on boot
rm -f "$MSG_ID_FILE"
echo "" > "$LIST_FILE"
echo "Tracker Started..." > tracker_debug.log

# --- Map Name Translation ---
if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="${SERVER_MAP:-Unknown Realm}"
fi

# --- Background Listener (Writes to File) ---
tail -F -n 0 "$LOG_FILE" | while read -r line; do
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"' | tr -d "'")
        if ! grep -q "^$NAME$" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
            echo "Added $NAME to list" >> tracker_debug.log
        fi
    fi

    if [[ "$line" == *"logged out"* ]] || [[ "$line" == *"ClosePort"* ]]; then
        while read -r p_name; do
            if [[ "$line" == *"$p_name"* ]]; then
                sed -i "/^$p_name$/d" "$LIST_FILE"
                echo "Removed $p_name from list" >> tracker_debug.log
            fi
        done < "$LIST_FILE"
    fi
done &

# --- Main Discord Update Loop ---
while true; do
    # Read stats
    players_online=$(grep -c . "$LIST_FILE" || echo "0")
    FINAL_LIST=$(paste -sd ", " "$LIST_FILE")
    [ -z "$FINAL_LIST" ] && FINAL_LIST="None online"

    JSON_PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "🎮 Soulmask Live Server Status",
    "color": 5763719,
    "fields": [
      {"name": "Server Name", "value": "${SERVER_NAME:-Soulmask Server}", "inline": false},
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

    if [ ! -f "$MSG_ID_FILE" ]; then
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}?wait=true")
        echo "$RESPONSE" | grep -oP '"id": "\K[0-9]+' > "$MSG_ID_FILE"
        echo "Created new message" >> tracker_debug.log
    else
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        curl -s -X PATCH -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}" > /dev/null
        echo "Updated message at $(date +'%T')" >> tracker_debug.log
    fi

    sleep 5
done
