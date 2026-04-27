#!/bin/bash

LOG_DIR="WS/Saved/Logs"
echo "Tracker Started..." > tracker_debug.log

if [ -z "$DISCORD_WEBHOOK" ]; then
    echo "Error: No Webhook URL provided!" >> tracker_debug.log
    exit 0
fi

# Function to send the webhook
send_webhook() {
    local p_name="$1"
    local m_name="${SERVER_MAP:-Unknown}"
    echo "Detected $p_name - Sending Webhook" >> tracker_debug.log
    
    curl -s -H "Content-Type: application/json" -X POST \
    -d "{\"embeds\": [{\"title\": \"🟢 Player Connected\", \"color\": 5763719, \"fields\": [{\"name\": \"Player Name\", \"value\": \"$p_name\", \"inline\": true}, {\"name\": \"Map\", \"value\": \"$m_name\", \"inline\": true}]}]}" \
    "$DISCORD_WEBHOOK" >> tracker_debug.log 2>&1
}

# Wait for logs
while [ ! -d "$LOG_DIR" ]; do sleep 5; done
LOG_FILE=$(ls -t $LOG_DIR/*.log 2>/dev/null | head -n 1)
while [ -z "$LOG_FILE" ]; do sleep 5; LOG_FILE=$(ls -t $LOG_DIR/*.log 2>/dev/null | head -n 1); done

echo "Tailing: $LOG_FILE" >> tracker_debug.log

# The magic fix: Using --line-buffered to prevent Linux from holding the text
tail -F --line-buffered "$LOG_FILE" | while read -r line; do
    if [[ "$line" == *"Join succeeded:"* ]]; then
        # Clean the name
        PLAYER_NAME=$(echo "$line" | sed 's/.*Join succeeded: //')
        # Fire it!
        send_webhook "$PLAYER_NAME"
    fi
done
