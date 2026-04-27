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
    echo "Sending Discord notification for: $p_name" >> tracker_debug.log
    
    curl -s -H "Content-Type: application/json" -X POST \
    -d "{\"embeds\": [{\"title\": \"🟢 Player Connected\", \"color\": 5763719, \"fields\": [{\"name\": \"Player Name\", \"value\": \"$p_name\", \"inline\": true}, {\"name\": \"Map\", \"value\": \"$m_name\", \"inline\": true}]}]}" \
    "$DISCORD_WEBHOOK" >> tracker_debug.log 2>&1
}

# Wait for logs folder
while [ ! -d "$LOG_DIR" ]; do sleep 2; done
# Find the log file
LOG_FILE=$(ls -t $LOG_DIR/*.log 2>/dev/null | head -n 1)
while [ -z "$LOG_FILE" ]; do sleep 2; LOG_FILE=$(ls -t $LOG_DIR/*.log 2>/dev/null | head -n 1); done

echo "Watching: $LOG_FILE" >> tracker_debug.log

# Get the current line count so we only look at NEW lines
last_line_count=$(wc -l < "$LOG_FILE")

while true; do
    current_line_count=$(wc -l < "$LOG_FILE")
    
    if [ "$current_line_count" -gt "$last_line_count" ]; then
        # Grab only the new lines since the last check
        new_lines=$(sed -n "$((last_line_count + 1)),${current_line_count}p" "$LOG_FILE")
        
        # Check if "Join succeeded:" is in those new lines
        if echo "$new_lines" | grep -q "Join succeeded:"; then
            # Extract name from the specific line that matched
            match_line=$(echo "$new_lines" | grep "Join succeeded:" | tail -n 1)
            PLAYER_NAME=$(echo "$match_line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"\'')
            send_webhook "$PLAYER_NAME"
        fi
        
        last_line_count=$current_line_count
    fi
    sleep 2 # Check every 2 seconds
done
