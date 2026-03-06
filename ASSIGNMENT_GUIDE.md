# Assignment Guide — ESP32 Client-Server TCP Communication

## Overview

Two identical ESP32 boards communicate over WiFi using TCP.
The **Server** reads potentiometers and controls LEDs.
The **Client** queries the Server and displays results.

```
ESP32 #1 (SERVER)                      ESP32 #2 (CLIENT)
┌────────────────────┐                ┌────────────────────┐
│ LED1 = WiFi status │                │ LED1 = WiFi status │
│ LED2 = Connected   │◄─── TCP ──────│ LED2 = Connected   │
│ LED3 = VR1 (PWM)   │   port 8080   │ LED3 = VR1 wins    │
│ LED4 = VR2 (PWM)   │               │ LED4 = VR2 wins    │
│ VR1, VR2 → InfluxDB│               │ SW1  = Connect     │
│ SW4  = Disconnect  │               │ SW4  = Disconnect  │
└────────────────────┘               └────────────────────┘
```

---

## Step 1: Pin Mapping

Check your board's silkscreen labels and update the `#define` lines at the top of each `.ino` file.

Default pin mapping (change if your board is different):

| Component | GPIO | Notes |
|-----------|------|-------|
| LED1 | 23 | WiFi indicator |
| LED2 | 22 | Connection indicator |
| LED3 | 21 | Server: VR1 PWM / Client: VR comparison |
| LED4 | 19 | Server: VR2 PWM / Client: VR comparison |
| SW1 (KEY1) | 13 | Client only: connect to server |
| SW4 (KEY4) | 16 | Both: disconnect |
| VR1 | 34 | Server only: potentiometer 1 (ADC) |
| VR2 | 35 | Server only: potentiometer 2 (ADC) |

**How to find your pin numbers:**
1. Look at the PCB silkscreen near each LED/button/potentiometer
2. Trace the line to the ESP32 pin header
3. Match with GPIO number (e.g., D34 = GPIO 34)

---

## Step 2: Configuration

Edit the top section of **both** `server.ino` and `client.ino`:

### WiFi (same for both boards)

```cpp
const char* WIFI_SSID     = "YourWiFiName";
const char* WIFI_PASSWORD = "YourWiFiPassword";
```

### Server IP (client.ino only)

1. Upload `server.ino` to ESP32 #1 first
2. Open Serial Monitor (115200 baud)
3. Note the IP address printed: `WiFi connected! IP: 192.168.x.x`
4. Put that IP in `client.ino`:

```cpp
const char* SERVER_IP = "192.168.x.x";
```

### InfluxDB (both boards)

```cpp
#define INFLUXDB_URL    "http://192.168.x.x:8086"
#define INFLUXDB_TOKEN  "your-token-here"
#define INFLUXDB_ORG    "your-org"
#define INFLUXDB_BUCKET "your-bucket"
```

If you don't have InfluxDB set up yet, the code will still work — it just prints an error to Serial and continues.

---

## Step 3: Upload

### Using Arduino IDE

1. Install ESP32 board support:
   - File → Preferences → Additional Board Manager URLs:
   - Add: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - Tools → Board Manager → search "esp32" → Install
2. Install library:
   - Sketch → Include Library → Manage Libraries
   - Search "ESP8266 Influxdb" → Install
3. Select board: Tools → Board → ESP32 Dev Module
4. Select port: Tools → Port → COMx
5. Upload `server.ino` to board #1
6. Upload `client.ino` to board #2

### Using arduino-cli

```bash
# One-time setup
arduino-cli config add board_manager.additional_urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core update-index
arduino-cli core install esp32:esp32
arduino-cli lib install "ESP8266 Influxdb"

# Upload server (change COM port)
arduino-cli compile --fqbn esp32:esp32:esp32 sketches/server
arduino-cli upload  --fqbn esp32:esp32:esp32 -p COM3 sketches/server

# Upload client (change COM port)
arduino-cli compile --fqbn esp32:esp32:esp32 sketches/client
arduino-cli upload  --fqbn esp32:esp32:esp32 -p COM4 sketches/client
```

---

## Step 4: Testing

### Test sequence

| Step | Action | Expected Result |
|------|--------|----------------|
| 1 | Power on both boards | LED1 blinks on both (connecting to WiFi) |
| 2 | Wait for WiFi | LED1 stays ON solid on both |
| 3 | Open Server Serial Monitor | Shows IP address and "Server ready" |
| 4 | Press SW1 on Client | LED2 ON on both boards |
| 5 | Turn VR1 potentiometer | Server: LED3 brightness changes, Serial shows VR1% |
| 6 | Turn VR2 potentiometer | Server: LED4 brightness changes, Serial shows VR2% |
| 7 | Set VR1 much higher than VR2 | Client: LED3 ON, LED4 OFF (after 3s) |
| 8 | Set VR2 much higher than VR1 | Client: LED4 ON, LED3 OFF (after 3s) |
| 9 | Set VR1 close to VR2 (within 5%) | Client: LED3+LED4 both ON |
| 10 | Press SW4 on either board | LED2, LED3, LED4 OFF on both |

### Serial Monitor output

**Server:**
```
WiFi connected! IP: 192.168.1.50
TCP Server listening on port 8080
[CONN] Client connected → LED2 ON, sent 'ok'
VR1: 45.2%  |  VR2: 30.1%
[QUERY] VR1 > VR2 (diff=15.1%) → sent VR1:45.2
[INFLUX] Server VR data written
```

**Client:**
```
WiFi connected! IP: 192.168.1.51
Press SW1 to connect to server...
[CONN] Connected! Received 'ok' → LED2 ON
[QUERY] Sent to server
[RECV] VR1 = 45.2%
  → VR1 dominant (45.2%) → LED3 ON
  → [INFLUX] Client data written
```

---

## Scoring Checklist (100 points)

Use this to verify all features work:

- [ ] **(15 pts)** LED1 blinks when WiFi connecting, stays ON when connected — both boards
- [ ] **(10 pts)** Press SW1 on Client → connects to Server
- [ ] **(5 pts)** LED2 ON on both boards when connected, Server sends "ok"
- [ ] **(5 pts)** LED2 OFF on both boards when disconnected
- [ ] **(15 pts)** Server: VR1%, VR2% on Serial + LED3/LED4 brightness + InfluxDB every 2s
- [ ] **(10 pts)** VR1 > VR2 (diff > 5%): Server sends VR1%, Client LED3 ON
- [ ] **(10 pts)** VR2 > VR1 (diff > 5%): Server sends VR2%, Client LED4 ON
- [ ] **(10 pts)** diff <= 5%: Server sends average, Client LED3+LED4 ON
- [ ] **(10 pts)** Client logs received VR values to InfluxDB
- [ ] **(5 pts)** SW4 on either board disconnects both
- [ ] **(5 pts)** LED3+LED4 OFF on both boards when disconnected

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| LED1 keeps blinking | Wrong WiFi SSID/password, or WiFi not in range |
| SW1 pressed but no connection | Check SERVER_IP matches Server's actual IP |
| "Connection FAILED" on Client | Server not running, or firewall blocking port 8080 |
| VR values always 0% | Wrong VR pin number — check board silkscreen |
| LED3/LED4 don't change | Wrong LED pin number — check board silkscreen |
| InfluxDB write error | Check URL/token/org/bucket — code works without InfluxDB |
| Upload fails "no serial data" | Hold BOOT button on ESP32 during upload, release after "Connecting..." |
