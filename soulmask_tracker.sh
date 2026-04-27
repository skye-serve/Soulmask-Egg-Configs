#!/bin/bash

echo "Tracker Started..." > tracker_debug.log

if [ -z "$DISCORD_WEBHOOK" ]; then
    echo "Error: No Webhook URL provided in panel!" >> tracker_debug.log
    exit 0
fi

echo "Webhook found! Waiting for log folder..." >> tracker_debug.log

LOG_DIR="WS/Saved/Logs"

while [ ! -d "$LOG_DIR" ]; do
    sleep 5
done

LOG_FILE=$(ls -t $LOG_DIR/*.log 2>/dev/null | head -n 1)

while [ -z "$LOG_FILE" ]; do
    sleep 5
    LOG_FILE=$(ls -t $LOG_DIR/*.log 2>/dev/null | head -n 1)
done

echo "Success! Tailing log file: $LOG_FILE" >> tracker_debug.log

MAP_NAME="${SERVER_MAP:-Unknown Map}"
SERVER_ID="${CROSS_ID:-1}"

tail -F -n 0 "$LOG_FILE" | {
    players_online=0
    while read -r line; do
        
        # --- PLAYER JOINED ---
        if [[ "$line" == *"Join succeeded:"* ]]; then
            # Extract player name AND strip out hidden newlines/quotes
            PLAYER_NAME=$(echo "$line" | awk -F 'Join succeeded:' '{print $2}' | awk '{print $1}' | tr -d '\r\n"\'')
            players_online=$((players_online + 1))
            
            echo "DETECTED JOIN: ${PLAYER_NAME}. Firing Webhook..." >> tracker_debug.log
            
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
            curl -s -H "Content-Type: application/json" -X POST -d "$JSON_PAYLOAD" "$DISCORD_WEBHOOK" >> tracker_debug.log 2>&1
        fi
    done
}
