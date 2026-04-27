#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"
MAP_FILE="steam_id_map.tmp"

# --- BRANDING ---
BOT_NAME="${BOT_NAME:-Skye Serve Monitor}"
BOT_LOGO="${BOT_LOGO:-https://raw.githubusercontent.com/parkervcp/pterodactyl-images/master/logos/soulmask.png}"

# Kill ghost processes
pkill -f tracker.sh

# 1. TOTAL RESET: Wipe everything for a fresh start
rm -f "$MSG_ID_FILE"
rm -f "payload.json"
> "$LIST_FILE"
> "$MAP_FILE" 

echo "--- SteamID Tracker Sync Started: $(date) ---" > tracker_debug.log

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
    
    # A. Link SteamID and Name during login handshake
    if [[ "$line" == *"Login request:"* ]] && [[ "$line" == *"Name="* ]]; then
        T_NAME=$(echo "$line" | sed 's/.*Name=\([^?& ]*\).*/\1/' | tr -d '"' | tr -d "'")
        T_ID=$(echo "$line" | sed 's/.*userId=\([0-9]*\).*/\1/' | grep -E '^[0-9]+$')
        
        if [ -n "$T_NAME" ] && [ -n "$T_ID" ]; then
            # Save the ID:Name relationship
            echo "$T_ID:$T_NAME" >> "$MAP_FILE"
            echo "[SYNC] Linked $T_NAME to $T_ID" >> tracker_debug.log
        fi
    fi

    # B. Confirm Join & Add to List
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -dc '[:print:]' | tr -d '"' | tr -d "'" | xargs)
        if [ -n "$NAME" ] && ! grep -qx "$NAME" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
            echo "[JOIN] $NAME added to online list" >> tracker_debug.log
        fi
    fi

    # C. Handle the Disconnect (Using the line you provided!)
    if [[ "$line" == *"player leave world."* ]]; then
        LEAVE_ID=$(echo "$line" | awk -F'world. ' '{print $2}' | tr -dc '0-9')
        
        if [ -n "$LEAVE_ID" ]; then
            # Look up the Name associated with this SteamID
            P_NAME=$(grep "^$LEAVE_ID:" "$MAP_FILE" | cut -d':' -f2 | tail -n 1)
            
            if [ -n "$P_NAME" ]; then
                grep -vx "$P_NAME" "$LIST_FILE" > "${LIST_FILE}.new" && mv "${LIST_FILE}.new" "$LIST_FILE"
                echo "[LEAVE] Removed $P_NAME (ID: $LEAVE_ID) from list" >> tracker_debug.log
            else
                echo "[DEBUG] ID $LEAVE_ID left, but no name was mapped." >> tracker_debug.log
            fi
        fi
    fi
done &

# --- Main Discord Loop ---
while true; do
    PLAYERS=$(grep -c "[^[:space:]]" "$LIST_FILE" || echo "0")
    
    if [ "$PLAYERS" -eq "0" ]; then
        FINAL_LIST="None online"
    else
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
