#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"

# --- BRANDING ---
# Change these to your own logo and name!
BOT_NAME="Skye Serve Soulmask Monitor"
BOT_LOGO="https://raw.githubusercontent.com/skye-serve/Soulmask-Egg-Configs/refs/heads/main/78691e4f-a6fd-4d12-ae6d-218f3a9c705c.jpg"

# Kill any existing tracker processes
pkill -f tracker.sh
rm -f "$MSG_ID_FILE"
echo "" > "$LIST_FILE"
echo "--- Tracker Vertical Fix Started: $(date) ---" > tracker_debug.log

# Map Name Translation
if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="Cloud Mist Forest"
fi

# --- Background Listener ---
tail -F -n 100 "$LOG_FILE" 2>/dev/null | while read -r line; do
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"' | tr -d "'" | xargs)
        if [ -n "$NAME" ] && ! grep -q "^$NAME$" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
        fi
    fi

    if [[ "$line" == *"logged out"* ]] || [[ "$line" == *"ClosePort"* ]]; then
        while read -r p_name; do
            if [ -n "$p_name" ] && [[ "$line" == *"$p_name"* ]]; then
                sed -i "/^$p_name$/d" "$LIST_FILE"
            fi
        done < "$LIST_FILE"
    fi
done &

# --- Main Discord Loop ---
while true; do
    # 1. Clean Player Count (Ensures it's a single digit, no '00')
    PLAYERS=$(grep -c "[^[:space:]]" "$LIST_FILE" || echo "0")
    PLAYERS=$(echo "$PLAYERS" | tr -d ' ')

    # 2. VERTICAL LIST LOGIC
    # This takes the names and replaces the spaces between them with a JSON-friendly \n
    if [ "$PLAYERS" -eq "0" ]; then
        FINAL_LIST="None online"
    else
        # This joins the lines with a literal \n for the JSON payload
        FINAL_LIST=$(sed '/^$/d' "$LIST_FILE" | tr -d '"' | paste -sd ',' - | sed 's/,/\\n/g')
    fi
    
    CUR_TIME=$(date +'%T')
    CLEAN_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')

    # 3. Build Payload (Now with escaped newlines)
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

    # 4. Send/Update Logic
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
            rm -f "$MSG_ID_FILE"
        fi
    fi

    sleep 10
done
