#!/bin/bash

# Exit if no webhook is provided
if [ -z "$DISCORD_WEBHOOK" ]; then
    exit 0
fi

LOG_FILE="WS/Saved/Logs/WSServer.log"
MAP_NAME="${SERVER_MAP:-Unknown Map}"
SERVER_ID="${CROSS_ID:-1}"

# Wait for the log file to actually exist
while [ ! -f "$LOG_FILE" ]; do
    sleep 5
done

# Tail the log file and read it line by line as it updates
tail -F -n 0 "$LOG_FILE" | {
    players_online=0
    while read -r line; do
        
        # --- PLAYER JOINED ---
        if [[ "$line" == *"Join succeeded:"* ]]; then
            # Extract player name (Grabs the first word after "Join succeeded:")
            PLAYER_NAME=$(echo "$line" | awk -F 'Join succeeded:' '{print $2}' | awk '{print $1}')
            players_online=$((players_online + 1))
            
            # Send the Webhook via cURL
            JSON_PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "🟢 Player Connected",
    "color": 5763719,
    "fields": [
      {"name": "Player Name", "value": "${PLAYER_NAME}", "inline": true},
      {"name": "Players Online", "value": "${players_online}", "inline": true},
      {"name": "Map", "value": "${MAP_NAME}", "inline": true},
      {"name": "Server Node ID", "value": "${SERVER_ID}", "inline": true}
    ],
    "footer": {"text": "Skye Serve Live Tracking"}
  }]
}
EOF
)
            curl -s -H "Content-Type: application/json" -X POST -d "$JSON_PAYLOAD" "$DISCORD_WEBHOOK"
            
        # --- PLAYER LEFT ---
        elif [[ "$line" == *"disconnected"* ]] || [[ "$line" == *"left the game"* ]]; then
            if [ $players_online -gt 0 ]; then
                players_online=$((players_online - 1))
            fi
            # (You can copy the JSON_PAYLOAD block here to send a leave message too!)
        fi
    done
}
