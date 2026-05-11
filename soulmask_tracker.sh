#!/bin/bash

# --- CONFIGURATION ---
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"
MAP_FILE="steam_id_map.tmp"
FLAG_FILE="shutdown.flag"

# --- WEBHOOKS ---
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

# PRE-SCAN existing logs to map players who were already online
while read -r line; do update_mapping "$line"; done < "$LOG_FILE"

if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="Cloud Mist Forest"
fi

# --- Background Listener (Status + Chat) ---
tail -F -n 0 "$LOG_FILE" 2>/dev/null | while read -r line; do
    line="${line//$'\r'/}"

    # === 💬 CHAT RELAY LOGIC ===
    if [[ "$line" == *"logWorldChat: Display:"* ]]; then
        if [[ "$line" != *"[Discord]"* ]]; then
            RAW_BRACKET=$(echo "$line" | grep -oP '(?<=Display: \[).*?(?=\])' | head -n 1)
            P_MSG=$(echo "$line" | sed 's/^.*Display: \[[^]]*\]//' | xargs)
            P_NAME=$(echo "$RAW_BRACKET" | sed 's/.*,//' | sed 's/(.*//' | xargs)

            if [ -z "$P_NAME" ]; then
                 P_NAME=$(echo "$RAW_BRACKET" | sed 's/(.*//' | xargs)
            fi

            if [ -n "$P_NAME" ] && [ -n "$P_MSG" ]; then
                TEMP_SNAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -d '"' | tr -dc '[:print:]')
                CLEAN_MSG=$(echo "$P_MSG" | sed 's/"/\\"/g')

                curl -s --max-time 8 -X POST -H "Content-Type: application/json" \
                -d "{\"username\": \"$P_NAME [$TEMP_SNAME]\", \"content\": \"$CLEAN_MSG\"}" \
                "$CHAT_WEBHOOK"
            fi
        fi
    fi

    # Trigger: Catch the shutdown command
    if [[ "$line" == *"TRY RUN ADMIN COMMAND: shutdown"* ]] || [[ "$line" == *"TRY RUN ADMIN COMMAND: Quit"* ]]; then
        touch "$FLAG_FILE"
        pkill -P $$ sleep 2>/dev/null
    fi

    update_mapping "$line"

    # --- Player Joins ---
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

    # --- Player Leaves ---
    if [[ "$line" == *"player leave world."* ]]; then
        LEAVE_ID=$(echo "$line" | grep -oE '[0-9]{17}')
        if [ -n "$LEAVE_ID" ]; then
            P_NAME=$(grep "^$LEAVE_ID:" "$MAP_FILE" | cut -d':' -f2 | tail -n 1 | tr -d '\r\n' | xargs)
            if [ -n "$P_NAME" ]; then
                sed -i "/$P_NAME/d" "$LIST_FILE"
                sed -i '/^$/d' "$LIST_FILE"

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
      {"name": "Online Players", "value": "\`\`\`\nServer is currently offline\n\`\`\`", "inline": false},
      {"name": "Recently Offline", "value": "\`\`\`\nServer is currently offline\n\`\`\`", "inline": false}
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

    PLAYERS=$(grep -c "[^[:space:]]" "$LIST_FILE" | awk '{print $1}')
    [ -z "$PLAYERS" ] && PLAYERS=0

    # 1. Format Online Players
    if [ "$PLAYERS" -eq 0 ]; then
        FINAL_LIST="None online"
    else
        FINAL_LIST=$(sed '/^$/d' "$LIST_FILE" | tr -d '"' | paste -sd ',' - | sed 's/,/\\n/g')
    fi

    # 2. Format Past/Offline Players (Last 20 to protect Discord character limits)
    if [ -s "$MAP_FILE" ]; then
        if [ "$PLAYERS" -eq 0 ]; then
            # If no one is online, just show the last 20 from the map
            OFFLINE_LIST=$(cut -d':' -f2 "$MAP_FILE" | tail -n 20 | tr -d '"' | paste -sd ',' - | sed 's/,/\\n/g')
        else
            # Filter out anyone currently online so they don't appear in both lists
            OFFLINE_LIST=$(cut -d':' -f2 "$MAP_FILE" | grep -v -F -x -f "$LIST_FILE" | tail -n 20 | tr -d '"' | paste -sd ',' - | sed 's/,/\\n/g')
        fi
        [ -z "$OFFLINE_LIST" ] && OFFLINE_LIST="None"
    else
        OFFLINE_LIST="None"
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
      {"name": "Online Players", "value": "\`\`\`\n$FINAL_LIST\n\`\`\`", "inline": false},
      {"name": "Recently Offline", "value": "\`\`\`\n$OFFLINE_LIST\n\`\`\`", "inline": false}
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
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" \
        -d @payload.json "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}")
        if [ "$HTTP_CODE" == "404" ]; then rm -f "$MSG_ID_FILE"; fi
    fi

    sleep 5
done
