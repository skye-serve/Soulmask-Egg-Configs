#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"
MAP_FILE="steam_id_map.tmp"

# --- BRANDING ---
BOT_NAME="${BOT_NAME:-Skye Serve Monitor}"
BOT_LOGO="https://raw.githubusercontent.com/skye-serve/Soulmask-Egg-Configs/refs/heads/main/78691e4f-a6fd-4d12-ae6d-218f3a9c705c.jpg"

# Kill ghost processes
pkill -f tracker.sh

# 1. TOTAL RESET
rm -f "$MSG_ID_FILE"
rm -f "payload.json"
> "$LIST_FILE"
> "$MAP_FILE" 

echo "--- Sync Started: $(date) ---" > tracker_debug.log

# Map Name Translation
if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="Cloud Mist Forest"
fi

# --- Background Listener ---
tail -F -n 2000 "$LOG_FILE" 2>/dev/null | while read -r line; do
    
    # A. Capture SteamID mapping (Improved regex for Soulmask)
    if [[ "$line" == *"Login request:"* ]]; then
        # Extracts Name= and userId= from the login URL line
        T_NAME=$(echo "$line" | sed -n 's/.*Name=\([^?& ]*\).*/\1/p' | tr -d '"' | tr -d "'")
        T_ID=$(echo "$line" | grep -oE 'userId=[0-9]+' | cut -d'=' -f2)
        
        if [ -n "$T_NAME" ] && [ -n "$T_ID" ]; then
            if ! grep -q "^$T_ID:" "$MAP_FILE"; then
                echo "$T_ID:$T_NAME" >> "$MAP_FILE"
                echo "[MAP] Linked $T_NAME to $T_ID" >> tracker_debug.log
            fi
        fi
    fi

    # B. Add to Online List
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -dc '[:print:]' | tr -d '"' | tr -d "'" | xargs)
        if [ -n "$NAME" ] && ! grep -qx "$NAME" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
            echo "[JOIN] $NAME joined" >> tracker_debug.log
        fi
    fi

    # C. Handle Disconnect (Using your exact log line format)
    if [[ "$line" == *"player leave world."* ]]; then
        LEAVE_ID=$(echo "$line" | grep -oE '[0-9]{17}')
        if [ -n "$LEAVE_ID" ]; then
            # Look up name in map
            P_NAME=$(grep "^$LEAVE_ID:" "$MAP_FILE" | cut -d':' -f2 | tail -n 1)
            if [ -n "$P_NAME" ]; then
                grep -vx "$P_NAME" "$LIST_FILE" > "${LIST_FILE}.new" && mv "${LIST_FILE}.new" "$LIST_FILE"
                echo "[LEAVE] Removed $P_NAME ($LEAVE_ID)" >> tracker_debug.log
            else
                echo "[WARN] $LEAVE_ID left, but mapping failed." >> tracker_debug.log
            fi
        fi
    fi
done &

# --- Main Discord Loop ---
while true; do
    # 1. Clean Player Count (Fixed the 'integer expression' error)
    PLAYERS=$(grep -c "[^[:space:]]" "$LIST_FILE" | head -n 1)
    if [ -z "$PLAYERS" ] || [ "$PLAYERS" -lt 0 ]; then PLAYERS=0; fi

    # 2. Format Vertical List
    if [ "$PLAYERS" -eq 0 ]; then
        FINAL_LIST="None online"
    else
        # Creates a proper vertical list for Discord JSON
        FINAL_LIST=$(sed '/^$/d' "$LIST_FILE" | tr -d '"' | paste -sd ',' - | sed 's/,/\\n/g')
    fi
    
    CUR_TIME=$(date +'%T')
    CLEAN_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')

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
        if [[ "$NEW_ID" =~ ^[0-9]+$ ]]; then echo "$NEW_ID" > "$MSG_ID_FILE"; fi
    else
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" -d @payload.json "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}")
        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "204" ]; then rm -f "$MSG_ID_FILE"; fi
    fi

    sleep 10
done
