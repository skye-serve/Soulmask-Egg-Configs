#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"
MAP_FILE="steam_id_map.tmp"
FLAG_FILE="shutdown.flag"

# --- WEBHOOKS ---
# These are pulled from your Panel Variables
DISCORD_WEBHOOK="${DISCORD_WEBHOOK}"
CHAT_WEBHOOK="${CHAT_WEBHOOK}"
LOG_WEBHOOK="${LOG_WEBHOOK}"

# --- BRANDING ---
BOT_NAME="Skye Serve Soulmask Monitor"
BOT_LOGO="https://raw.githubusercontent.com/skye-serve/Soulmask-Egg-Configs/refs/heads/main/78691e4f-a6fd-4d12-ae6d-218f3a9c705c.jpg"

# --- GHOST KILLER ---
for pid in $(pgrep -f tracker.sh); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

# 1. CLEAN RESET
rm -f "payload.json"
rm -f "$FLAG_FILE"
> "$LIST_FILE" 
touch "$MAP_FILE"

echo "--- Stable Tracker & Chat Relay Started: $(date) ---" > tracker_debug.log

update_mapping() {
    local raw_line="$1"
    if [[ "$raw_line" == *"player ready."* ]]; then
        local t_id=$(echo "$raw_line" | sed -n 's/.*Netuid:\([0-9]*\).*/\1/p' | tr -d '\r\n ')
        local t_name=$(echo "$raw_line" | sed -n 's/.*Name:\(.*\)/\1/p' | tr -d '\r\n' | xargs)
        
        if [ -n "$t_name" ] && [ -n "$t_id" ]; then
            grep -vx "^$t_id:.*" "$MAP_FILE" > "${MAP_FILE}.new" 2>/dev/null
            mv "${MAP_FILE}.new" "$MAP_FILE" 2>/dev/null
            echo "$t_id:$t_name" >> "$MAP_FILE"
        fi
    fi
}

# PRE-SCAN
while read -r line; do update_mapping "$line"; done < "$LOG_FILE"

if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="Cloud Mist Forest"
fi

# --- Background Listener (Status + Chat) ---
# REMOVED 'tr' from the pipeline to prevent buffering/hanging
tail -F -n 0 "$LOG_FILE" 2>/dev/null | while read -r line; do
    # Clean the line inside the loop (strips carriage returns)
    line="${line//$'\r'/}"

    # === 💬 CHAT RELAY LOGIC (WITH ECHO PREVENTION) ===
    if [[ "$line" == *"logWorldChat: Display:"* ]]; then
        echo "[CHAT DEBUG] Seen in log: $line" >> tracker_debug.log
        
        # Loop Prevention: Ignore messages containing [Discord]
        if [[ "$line" != *"[Discord]"* ]]; then
            # Refined extraction to handle names better (Updated for new Soulmask log format)
            P_NAME=$(echo "$line" | sed -n 's/.*Display: \[\(.*\)(.*/\1/p' | xargs)
            P_MSG=$(echo "$line" | sed -n 's/.*)\]\(.*\)/\1/p' | xargs)

            if [ -n "$P_NAME" ] && [ -n "$P_MSG" ]; then
                echo "[CHAT DEBUG] Sending message: $P_NAME: $P_MSG" >> tracker_debug.log
                
                # Grab the Server Name quickly for the Echo Prevention tag
                TEMP_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')

                curl -s --max-time 8 -X POST -H "Content-Type: application/json" \
                -d "{\"username\": \"$P_NAME [$TEMP_SNAME]\", \"content\": \"$P_MSG\"}" \
                "$CHAT_WEBHOOK"
            fi
        fi
    fi

    # Trigger #1: Catch the shutdown command
    if [[ "$line" == *"TRY RUN ADMIN COMMAND: shutdown"* ]] || [[ "$line" == *"TRY RUN ADMIN COMMAND: Quit"* ]]; then
        echo "[SHUTDOWN] Exit sequence detected!" >> tracker_debug.log
        touch "$FLAG_FILE"
        pkill -P $$ sleep 2>/dev/null
    fi

    update_mapping "$line"

    # ----------------------------------------------------
    # 📝 PLAYER CONNECTION LOGS (Joins -> #cluster-logs)
    # ----------------------------------------------------
    if [[ "$line" == *"player ready."* ]]; then
        JOIN_NAME=$(echo "$line" | sed -n 's/.*Name:\(.*\)/\1/p' | tr -d '\r\n' | xargs)
        JOIN_ID=$(echo "$line" | sed -n 's/.*Netuid:\([0-9]*\).*/\1/p' | tr -d '\r\n ')
        
        if [ -n "$JOIN_NAME" ] && [ -n "$LOG_WEBHOOK" ]; then
            TEMP_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')
            
            cat <<EOF > join_payload.json
{
  "embeds": [{
    "title": "🟢 Player Joined",
    "color": 3066993,
    "fields": [
      {"name": "Player", "value": "$JOIN_NAME", "inline": true},
      {"name": "Steam ID", "value": "$JOIN_ID", "inline": true},
      {"name": "Server", "value": "$TEMP_SNAME", "inline": false}
    ]
  }]
}
EOF
            curl -s --max-time 5 -H "Content-Type: application/json" -X POST -d @join_payload.json "$LOG_WEBHOOK"
        fi
    fi

    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n' | tr -d '"' | tr -d "'" | xargs)
        if [ -n "$NAME" ] && ! grep -qx "$NAME" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
        fi
    fi

    # === 🚪 IMPROVED LEAVE LOGIC + LEAVE LOGS ===
    if [[ "$line" == *"player leave world."* ]]; then
        LEAVE_ID=$(echo "$line" | grep -oE '[0-9]{17}')
        if [ -n "$LEAVE_ID" ]; then
            P_NAME=$(grep "^$LEAVE_ID:" "$MAP_FILE" | cut -d':' -f2 | tail -n 1 | tr -d '\r\n' | xargs)
            if [ -n "$P_NAME" ]; then
                # THE BULLDOZER: Delete any line containing this name, ignoring exact whitespace matches
                sed -i "/$P_NAME/d" "$LIST_FILE"
                
                # Clean up any empty lines left behind in the file
                sed -i '/^$/d' "$LIST_FILE"

                # ----------------------------------------------------
                # 📝 PLAYER CONNECTION LOGS (Leaves -> #cluster-logs)
                # ----------------------------------------------------
                if [ -n "$LOG_WEBHOOK" ]; then
                    TEMP_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')
                    cat <<EOF > leave_payload.json
{
  "embeds": [{
    "title": "🔴 Player Left",
    "color": 15548997,
    "fields": [
      {"name": "Player", "value": "$P_NAME", "inline": true},
      {"name": "Steam ID", "value": "$LEAVE_ID", "inline": true},
      {"name": "Server", "value": "$TEMP_SNAME", "inline": false}
    ]
  }]
}
EOF
                    curl -s --max-time 5 -H "Content-Type: application/json" -X POST -d @leave_payload.json "$LOG_WEBHOOK"
                fi

            else
                # Aggressive Fallback: If only 1 player is online, just wipe the list.
                ONLINE_COUNT=$(grep -c "[^[:space:]]" "$LIST_FILE")
                if [ "$ONLINE_COUNT" -le 1 ]; then 
                    > "$LIST_FILE"
                fi
            fi
        fi
    fi
done &
TAIL_PID=$!

# --- Main Discord Loop (Status Embed) ---
while true; do
    CUR_TIME=$(date +'%T')
    CLEAN_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')
    
    # Heartbeat to debug log to ensure loop is running
    echo "[HEARTBEAT] Monitor Loop active at $CUR_TIME" >> tracker_debug.log

    # Check for Shutdown Flag
    if [ -f "$FLAG_FILE" ]; then
        cat <<EOF > payload.json
{
  "username": "$BOT_NAME",
  "avatar_url": "$BOT_LOGO",
  "embeds": [{
    "title": "🎮 Soulmask Live Server Status",
    "color": 15548997, 
    "fields": [
      {"name": "Server Name", "value": "$CLEAN_SNAME", "inline": false},
      {"name": "Status", "value": "🔴 Offline / Restarting", "inline": true},
      {"name": "Map", "value": "$DISPLAY_MAP", "inline": true},
      {"name": "Current Players", "value": "0", "inline": true},
      {"name": "Online Players", "value": "\`\`\`\nServer is currently offline\n\`\`\`", "inline": false}
    ],
    "footer": {"text": "Last Updated: $CUR_TIME | Skye Serve"}
  }]
}
EOF
        if [ -s "$MSG_ID_FILE" ]; then
            MESSAGE_ID=$(cat "$MSG_ID_FILE")
            curl -s -o /dev/null -X PATCH -H "Content-Type: application/json" -d @payload.json "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}"
        fi
        rm -f "$FLAG_FILE"
        exit 0
    fi

    # Normal Online Payload...
    PLAYERS=$(grep -c "[^[:space:]]" "$LIST_FILE" | awk '{print $1}')
    [ -z "$PLAYERS" ] && PLAYERS=0

    if [ "$PLAYERS" -eq 0 ]; then
        FINAL_LIST="None online"
    else
        FINAL_LIST=$(sed '/^$/d' "$LIST_FILE" | tr -d '"' | paste -sd ',' - | sed 's/,/\\n/g')
    fi

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
      {"name": "Online Players", "value": "\`\`\`\n$FINAL_LIST\n\`\`\`", "inline": false}
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
        if [ "$HTTP_CODE" == "404" ]; then rm -f "$MSG_ID_FILE"; fi
    fi

    sleep 5
done
