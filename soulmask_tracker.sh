#!/bin/bash

LOG_FILE="WS/Saved/Logs/WS.log"
MSG_ID_FILE="discord_message_id.txt"
LIST_FILE="current_players.tmp"

# Kill any existing tracker processes
PID_TO_KILL=$(pgrep -f tracker.sh | grep -v $$)
if [ -n "$PID_TO_KILL" ]; then kill $PID_TO_KILL; fi

# Fresh start
rm -f "$MSG_ID_FILE"
echo "" > "$LIST_FILE"
echo "--- Tracker Reset: $(date) ---" > tracker_debug.log

# Map Name Translation
if [ "$SERVER_MAP" == "Level01_Main" ]; then
    DISPLAY_MAP="Cloud Mist Forest"
elif [ "$SERVER_MAP" == "DLC_Level01_Main" ]; then
    DISPLAY_MAP="Shifting Sands"
else
    DISPLAY_MAP="Cloud Mist Forest"
fi

# --- Background Listener ---
tail -F -n 0 "$LOG_FILE" 2>/dev/null | while read -r line; do
    if [[ "$line" == *"Join succeeded:"* ]]; then
        NAME=$(echo "$line" | sed 's/.*Join succeeded: //' | tr -dc '[:print:]' | tr -d '"' | tr -d "'")
        if ! grep -q "^$NAME$" "$LIST_FILE"; then
            echo "$NAME" >> "$LIST_FILE"
        fi
    fi
    if [[ "$line" == *"logged out"* ]] || [[ "$line" == *"ClosePort"* ]]; then
        while read -r p_name; do
            if [[ "$line" == *"$p_name"* ]]; then
                sed -i "/^$p_name$/d" "$LIST_FILE"
            fi
        done < "$LIST_FILE"
    fi
done &

# --- Main Update Loop ---
while true; do
    # 1. Sanitize all variables (Remove non-printable characters and quotes)
    CLEAN_NAME=$(echo "${SERVER_NAME:-Soulmask Server}" | tr -dc '[:print:]' | tr -d '"')
    PLAYERS=$(grep -c . "$LIST_FILE" || echo "0")
    LIST_DATA=$(paste -sd ", " "$LIST_FILE" | tr -dc '[:print:]' | tr -d '"')
    [ -z "$LIST_DATA" ] && LIST_DATA="None online"
    CUR_TIME=$(date +'%T')

    # 2. Build JSON as a single line to prevent "Broken JSON" errors
    JSON_PAYLOAD="{\"embeds\":[{\"title\":\"🎮 Soulmask Live Server Status\",\"color\":5763719,\"fields\":[{\"name\":\"Server Name\",\"value\":\"$CLEAN_NAME\",\"inline\":false},{\"name\":\"Status\",\"value\":\"🟢 Online\",\"inline\":true},{\"name\":\"Map\",\"value\":\"$DISPLAY_MAP\",\"inline\":true},{\"name\":\"Current Players\",\"value\":\"$PLAYERS\",\"inline\":true},{\"name\":\"Online Players\",\"value\":\"\`\`\`$LIST_DATA\`\`\`\",\"inline\":false}],\"footer\":{\"text\":\"Last Updated: $CUR_TIME | Skye Serve\"}}]}"

    if [ ! -s "$MSG_ID_FILE" ]; then
        echo "[STEP 1] Sending initial message..." >> tracker_debug.log
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}?wait=true")
        
        # Extract ID safely
        NEW_ID=$(echo "$RESPONSE" | sed -n 's/.*"id": "\([0-9]*\)".*/\1/p')
        
        if [[ "$NEW_ID" =~ ^[0-9]+$ ]]; then
            echo "$NEW_ID" > "$MSG_ID_FILE"
            echo "[STEP 2] Success! ID: $NEW_ID" >> tracker_debug.log
        else
            echo "[ERROR] Discord rejected JSON: $RESPONSE" >> tracker_debug.log
        fi
    else
        MESSAGE_ID=$(cat "$MSG_ID_FILE")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "${DISCORD_WEBHOOK}/messages/${MESSAGE_ID}")
        
        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "204" ]; then
            echo "[RETRY] Edit failed (HTTP $HTTP_CODE). Resetting..." >> tracker_debug.log
            rm -f "$MSG_ID_FILE"
        else
            echo "[OK] Updated at $CUR_TIME" >> tracker_debug.log
        fi
    fi

    sleep 10
done
