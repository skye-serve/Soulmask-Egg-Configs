#!/bin/bash

# Configuration
LOG_FILE="WS/Saved/Logs/WS.log"
MAP_NAME="${SERVER_MAP:-Level01_Main}"
NODE_ID="${CROSS_ID:-1}"

# Initialize counters and temporary storage
players_online=0
temp_steamid="Unknown"
temp_ip="Unknown"

# Wait for log file
while [ ! -f "$LOG_FILE" ]; do sleep 5; done
echo "Monitoring for pro features: $LOG_FILE"

# Process the log line-by-line
tail -F -n 0 "$LOG_FILE" | while read -r line; do

    # 1. Capture Steam ID (Appears during login request)
    if [[ "$line" == *"Login request: "* ]]; then
        temp_steamid=$(echo "$line" | grep -oP 'userId: \K[0-9]+' || echo "Unknown")
    fi

    # 2. Capture IP Address (Appears during connection)
    if [[ "$line" == *"RemoteAddr: "* ]]; then
        temp_ip=$(echo "$line" | grep -oP 'RemoteAddr: \K[0-9.]+' || echo "Unknown")
    fi

    # 3. Capture Join Success & Fire Webhook
    if [[ "$line" == *"Join succeeded:"* ]]; then
        PLAYER_NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"' | tr -d "'")
        players_online=$((players_online + 1))

        # Build the exact JSON from your screenshot
        JSON_PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "🟢 Player Joined",
    "color": 5763719,
    "fields": [
      {"name": "Player Name", "value": "${PLAYER_NAME}", "inline": true},
      {"name": "Steam ID", "value": "${temp_steamid}", "inline": true},
      {"name": "IP Address", "value": "${temp_ip}", "inline": true},
      {"name": "Total Players Online", "value": "${players_online}", "inline": false},
      {"name": "Map", "value": "${MAP_NAME}", "inline": true},
      {"name": "Server Node ID", "value": "${NODE_ID}", "inline": true}
    ],
    "footer": {"text": "Powered by Skye Serve"}
  }]
}
EOF
)
        # Send to Discord
        curl -s -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$DISCORD_WEBHOOK"
        
        # Reset temps for the next player
        temp_steamid="Unknown"
        temp_ip="Unknown"
    fi

    # 4. Handle Disconnects (To keep the player count accurate)
    if [[ "$line" == *"ClosePort"* ]] || [[ "$line" == *"logged out"* ]]; then
        if [ $players_online -gt 0 ]; then
            players_online=$((players_online - 1))
        fi
    fi

done
