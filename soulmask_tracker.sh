#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"
MAP_FILE="steam_id_map.tmp"

# --- BRANDING ---
BOT_NAME="Skye Serve Soulmask Monitor"
BOT_LOGO="https://raw.githubusercontent.com/skye-serve/Soulmask-Egg-Configs/refs/heads/main/78691e4f-a6fd-4d12-ae6d-218f3a9c705c.jpg"

# Kill ghost processes
pkill -f tracker.sh

# 1. CLEAN RESET
rm -f "$MSG_ID_FILE"
rm -f "payload.json"
> "$LIST_FILE" 
touch "$MAP_FILE"

echo "--- Soulmask Final Sync Started: $(date) ---" > tracker_debug.log

# 2. THE NEW MAPPING LOGIC
# This specifically looks for the 'player ready' line you found
update_mapping() {
    local raw_line="$1"
    if [[ "$raw_line" == *"player ready."* ]]; then
        # Extract SteamID (Netuid)
        local t_id=$(echo "$raw_line" | sed -n 's/.*Netuid:\([0-9]*\).*/\1/p')
        # Extract Name
        local t_name=$(echo "$raw_line" | sed -n 's/.*Name:\(.*\)/\1/p' | xargs)
        
        if [ -n "$t_name" ] && [ -n "$t_id" ]; then
            # We overwrite any old mapping for this ID to ensure it's current
            grep -vx "^$t_id:.*" "$MAP_FILE" > "${MAP_FILE}.new" 2>/dev/null
            mv "${MAP_FILE}.new" "$MAP_FILE" 2>/dev/null
            echo "$t_id:$t_name" >> "$MAP_FILE"
            echo "[MAP] Linked $t_name to $t_id" >> tracker_debug.log
        fi
    fi
}

# 3. PRE-SCAN: Scan history to learn who everyone is
while read -r line; do update_mapping "$line"; done < "$LOG_FILE"

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
    
    # A. Mapping Event (Player Ready)
    update_mapping "$line"

    # B. Join Event
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -dc '[:print:]' | tr -d '"' | tr -d "'" | xargs)
        if [ -n "$NAME" ] && ! grep -qx "$NAME" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
            echo "[JOIN] $NAME online" >> tracker_debug.log
        fi
    fi

    # C. Leave Event (Using SteamID)
    if [[ "$line" == *"player leave world."* ]]; then
        LEAVE_ID=$(echo "$line" | grep -oE '[0-9]{17}')
        if [ -n "$LEAVE_ID" ]; then
            P_NAME=$(grep "^$LEAVE_ID:" "$MAP_FILE" | cut -d':' -f2 | tail -n 1)
            
            if [ -n "$P_NAME" ]; then
                grep -vx "$P_NAME" "$LIST_FILE" > "${LIST_FILE}.new" && mv "${LIST_FILE}.new" "$LIST_FILE"
                echo "[LEAVE] Removed $P_NAME ($LEAVE_ID)" >> tracker_debug.log
            else
                # FALLBACK: If only 1 person is on, clear them.
                ONLINE_COUNT=$(grep -c "[^[:space:]]" "$LIST_FILE")
                if [ "$ONLINE_COUNT" -le 1 ]; then
                    > "$LIST_FILE"
                    echo "[LEAVE] Mapping missing, cleared list anyway." >> tracker_debug.log
                fi
            fi
        fi
    fi
done &

# --- Main Discord Loop ---
while true; do
    # Get player count as a single clean number
    PLAYERS=$(grep -c "[^[:space:]]" "$LIST_FILE" | awk '{print $1}')
    [ -z "$PLAYERS" ] && PLAYERS=0

    if [ "$PLAYERS" -eq 0 ]; then
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
        if [[ "$NEW_ID" =~ ^[0-9]+$ ]]; then echo "$NEW_ID" > "$MSG_ID_FILE"; fi
    else
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" -d @payload.json "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}")
        [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "204" ] && rm -f "$MSG_ID_FILE"
    fi

    sleep 10
done
