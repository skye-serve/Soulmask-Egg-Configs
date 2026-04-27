#!/bin/bash

# Define the log path directly
LOG_FILE="WS/Saved/Logs/WS.log"

# Wait for the server to create the log file
while [ ! -f "$LOG_FILE" ]; do
    sleep 5
done

echo "Tailing log: $LOG_FILE"

# The most reliable way to watch a log in Linux:
tail -F --line-buffered "$LOG_FILE" | grep --line-buffered "Join succeeded:" | while read -r line; do
    
    # 1. Extract the name and strip EVERY possible hidden character (newlines, returns, quotes)
    PLAYER_NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n\"'\''')
    
    # 2. Fire a simple text message (Not an embed, just to test connection)
    # This is much harder for Discord to reject as "Invalid JSON"
    curl -X POST -H "Content-Type: application/json" \
         -d "{\"content\": \"🟢 **$PLAYER_NAME** has joined the Soulmask server!\"}" \
         "$DISCORD_WEBHOOK"
         
done
