#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"

# --- BRANDING ---
BOT_NAME="Skye Serve Soulmask Monitor"
BOT_LOGO="https://raw.githubusercontent.com/skye-serve/Soulmask-Egg-Configs/refs/heads/main/78691e4f-a6fd-4d12-ae6d-218f3a9c705c.jpg"

# Kill any ghost processes
pkill -f tracker.sh

# 1. TOTAL RESET: Wipe the player list and message ID on every boot
# This ensures we start with 0 players and a fresh Discord message
rm -f "$MSG_ID_FILE"
rm -f "payload.json"
> "$LIST_FILE" 

echo "--- Tracker Reset & Started: $(date) ---" > tracker_debug.log

# Map Name Translation
if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="Cloud Mist Forest"
fi

# --- Background Listener ---
# We use -n 0 so we only listen for NEW joins starting NOW
tail -F -n 0 "$LOG_FILE" 2>/dev/null | while read -r line; do
    
    # Capture Joins
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"' | tr -d "'" | xargs)
        if [ -n "$NAME" ] && ! grep -q "^$NAME$" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
            echo "[EVENT] $NAME joined" >> tracker_debug.log
        fi
    fi

    # Broad Leave Detection (Catches almost any disconnect)
    if [[ "$line" == *"logged out"* ]] || [[ "$line" == *"ClosePort"* ]] || [[ "$line" == *"CleanupSession"* ]] || [[ "$line" == *"DestroyPlayer"* ]]; then
        # Check if any name in our list appears in this log line
        while read -r p_name; do
            if [ -n "$p_name" ] && [[ "$line" == *"$p_name"* ]]; then
                sed -i "/^$p_name$/d" "$LIST_FILE"
                echo "[EVENT] $p_name left" >> tracker_debug.log
            fi
        done < "$LIST_FILE"
    fi
done &

# --- Main Discord Loop ---
while true; do
    # Count real lines only
    PLAYERS=$(grep -c "[^[:space:]]" "$LIST_FILE" || echo "0")
    
    # Format Vertical List for JSON
    if [ "$PLAYERS" -eq "0" ]; then
        FINAL_LIST="None online"
    else
        # Joins names with a literal \n for Discord to read vertically
        FINAL_LIST=$(sed '/^$/d' "$LIST_FILE" | tr -d '"' | paste -sd ',' - | sed 's/,/\\n/g')
    fi
    
    CUR_TIME=$(date +'%T')
    CLEAN_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')

    # Build Payload
    cat <<EOF > payload.json
{
  "username": "$BOT_NAME",
  "avatar_url": "$BOT_LOGO",
  "embeds": [{
    "title": "🎮 Soulmask Live Server Status",
    "color": 5763719,
    "fields": [
      {"name": "Server Name", "value": "$CLEAN_SNAME", "inline": false},
      {"name": "Status", "value": "🟢 Online", "inline": true},
      {"name": "Map", "value": "$DISPLAY_MAP", "inline": true},
      {"name": "Current Players", "value": "$PLAYERS", "inline": true},
      {"name": "Online Players", "value": "\`\`\`\\n$FINAL_LIST\\n\`\`\`", "inline": false}
    ],
    "footer": {"text": "Last Updated: $CUR_TIME | Skye Serve"}
  }]
}
EOF

    if [ ! -s "$MSG_ID_FILE" ]; then
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d @payload.json "${DISCORD_WEBHOOK}?wait=true")
        NEW_ID=$(echo "$RESPONSE" | grep -o '"id":"[0-9]*"' | head -n 1 | cut -d'"' -f4)
        if [[ "$NEW_ID" =~ ^[0-9]+$ ]]; then
            echo "$NEW_ID" > "$MSG_ID_FILE"
        fi
    else
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" -d @payload.json "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}")
        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "204" ]; then
            rm -f "$MSG_ID_FILE" # If message was deleted, restart with a new one
        fi
    fi

    sleep 10
done
