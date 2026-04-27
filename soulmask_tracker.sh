#!/bin/bash

# Path to the log
LOG_FILE="WS/Saved/Logs/WS.log"

# Wait for the server to create the log file
while [ ! -f "$LOG_FILE" ]; do
    sleep 5
done

echo "Monitoring log: $LOG_FILE"

# Standard tail -F works on all versions of Linux
tail -F "$LOG_FILE" | while read -r line; do
    
    # Check if the line contains the join message
    if [[ "$line" == *"Join succeeded:"* ]]; then
        
        # Extract name and strip hidden characters, double quotes, and single quotes safely
        PLAYER_NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -d '\r\n"' | tr -d "'")
        
        # Send simple message to Discord
        curl -s -X POST -H "Content-Type: application/json" \
             -d "{\"content\": \"🟢 **$PLAYER_NAME** has joined the Soulmask server!\"}" \
             "$DISCORD_WEBHOOK"
             
        echo "Sent join for: $PLAYER_NAME"
    fi
done
