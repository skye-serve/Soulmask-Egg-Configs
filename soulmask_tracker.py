import time, os, json, sys
import urllib.request

WEBHOOK_URL = os.environ.get('DISCORD_WEBHOOK')
MAP_NAME = os.environ.get('SERVER_MAP', 'Unknown Map')
SERVER_ID = os.environ.get('CROSS_ID', '1')
LOG_FILE = 'WS/Saved/Logs/WSServer.log'

if not WEBHOOK_URL or WEBHOOK_URL.strip() == "":
    sys.exit(0)

players_online = 0

def send_to_discord(player_name, is_joining=True):
    global players_online
    title = "🟢 Player Connected" if is_joining else "🔴 Player Disconnected"
    color = 5763719 if is_joining else 15548997
    
    data = {
        "embeds": [{
            "title": title,
            "color": color,
            "fields": [
                {"name": "Player Name", "value": player_name, "inline": True},
                {"name": "Players Online", "value": str(players_online), "inline": True},
                {"name": "Map", "value": MAP_NAME, "inline": True},
                {"name": "Server Node ID", "value": SERVER_ID, "inline": True}
            ],
            "footer": {"text": "Skye Serve Live Tracking"}
        }]
    }
    
    req = urllib.request.Request(WEBHOOK_URL, data=json.dumps(data).encode('utf-8'), headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'})
    try:
        urllib.request.urlopen(req)
    except:
        pass

while not os.path.exists(LOG_FILE):
    time.sleep(5)

with open(LOG_FILE, 'r', encoding='utf-8', errors='ignore') as file:
    file.seek(0, 2)
    
    while True:
        line = file.readline()
        if not line:
            time.sleep(0.5)
            continue
        
        if "Join succeeded:" in line:
            try:
                player_name = line.split("Join succeeded:")[1].strip().split()[0]
                players_online += 1
                send_to_discord(player_name, is_joining=True)
            except:
                pass
