#!/bin/bash

# Configuration
LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
rm -f "$MSG_ID_FILE"

# Translate Map Name
if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="The Main Map"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="${SERVER_MAP:-Unknown}"
fi

# Initialize Variables
players_online=0
player_list=""

# --- Background Listener for Logs ---
tail -F -n 0 "$LOG_FILE" | while read -r line; do
    
    # Handle Joins
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"' | tr -d "'")
        # Add name only if not already in list
        if [[ ! "$player_list" == *"$NAME"* ]]; then
            players_online=$((players_online + 1))
            if [ -z "$player_list" ]; then player_list="$NAME"; else player_list="$player_list, $NAME"; fi
        fi
    fi

    # Handle Leaves (Smart Removal)
    if [[ "$line" == *"logged out"* ]] || [[ "$line" == *"ClosePort"* ]]; then
        # Try to extract name from the logout line if possible
        L_NAME=$(echo "$line" | grep -oP 'player \K[^ ]+' || echo "")
        
        if [ $players_online -gt 0 ]; then
            players_online=$((players_online - 1))
            # Remove the name from the comma-separated list
            player_list=$(echo "$player_list" | sed "s/$L_NAME//g; s/,,/,/g; s/^,//; s/,$//; s/ ,/ /g")
        fi
        if [ $players_online -le 0 ]; then players_online=0; player_list=""; fi
    fi
done &

# --- Main Update Loop ---
while true; do
    # Display "None" if list is empty
    FINAL_LIST="${player_list:-None online}"

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
    else
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        curl -s -X PATCH -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}" > /dev/null
    fi

    sleep 10 
done
