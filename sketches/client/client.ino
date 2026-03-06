/*
 * ===== CLIENT.INO =====
 * TCP Client — ESP32 Client-Server VR Communication
 *
 * Scoring covered:
 *   1. WiFi + LED1 blink/solid             (15 pts)
 *   2. sw1 → connect to Server             (10 pts)
 *   3. LED2 ON when connected + receive "ok" (5 pts)
 *   4. LED2 OFF when disconnected           (5 pts)
 *   6. Query every 3s + LED3/LED4 logic + InfluxDB  (40 pts)
 *   7. sw4 disconnect                       (5 pts)
 *   8. LED3/LED4 OFF when disconnected      (5 pts)
 *
 * Setup (arduino-cli):
 *   arduino-cli config add board_manager.additional_urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
 *   arduino-cli core update-index && arduino-cli core install esp32:esp32
 *   arduino-cli lib install "ESP8266 Influxdb"
 *
 * FQBN: esp32:esp32:esp32   (or esp32:esp32:esp32dev)
 */

#include <WiFi.h>
#include <InfluxDbClient.h>

// ╔══════════════════════════════════════════════════════════╗
// ║  CONFIGURATION — แก้ตรงนี้ให้ตรงกับของจริง                    ║
// ╚══════════════════════════════════════════════════════════╝

// WiFi (ต้องเหมือนกับ Server)
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// Server IP — ดูจาก Serial Monitor ของ Server ตอนเปิด
const char* SERVER_IP   = "192.168.1.100";
#define SERVER_PORT 8080

// InfluxDB (InfluxDB 2.x)
#define INFLUXDB_URL    "http://YOUR_INFLUXDB_IP:8086"
#define INFLUXDB_TOKEN  "YOUR_TOKEN"
#define INFLUXDB_ORG    "YOUR_ORG"
#define INFLUXDB_BUCKET "YOUR_BUCKET"

// ╔══════════════════════════════════════════════════════════╗
// ║  PIN MAPPING — ต้องตรงกับบอร์ดของคุณ                        ║
// ╚══════════════════════════════════════════════════════════╝

#define PIN_LED1  23      // WiFi status
#define PIN_LED2  22      // TCP connection status
#define PIN_LED3  21      // VR comparison indicator
#define PIN_LED4  19      // VR comparison indicator

#define PIN_SW1   13      // Connect button (KEY1)
#define PIN_SW4   16      // Disconnect button (KEY4)

// ╔══════════════════════════════════════════════════════════╗
// ║  GLOBALS                                                ║
// ╚══════════════════════════════════════════════════════════╝

WiFiClient tcpClient;

InfluxDBClient influxClient(INFLUXDB_URL, INFLUXDB_ORG, INFLUXDB_BUCKET, INFLUXDB_TOKEN);
Point sensorData("client_vr");

bool serverConnected     = false;
unsigned long lastQuery  = 0;
unsigned long lastBlink  = 0;
bool led1Blink           = false;

// ╔══════════════════════════════════════════════════════════╗
// ║  SETUP                                                  ║
// ╚══════════════════════════════════════════════════════════╝

void setup() {
  Serial.begin(115200);
  Serial.println("\n===== CLIENT STARTING =====");

  // --- Pins ---
  pinMode(PIN_LED1, OUTPUT);
  pinMode(PIN_LED2, OUTPUT);
  pinMode(PIN_LED3, OUTPUT);
  pinMode(PIN_LED4, OUTPUT);
  pinMode(PIN_SW1, INPUT_PULLUP);
  pinMode(PIN_SW4, INPUT_PULLUP);

  // All LEDs off
  digitalWrite(PIN_LED1, LOW);
  digitalWrite(PIN_LED2, LOW);
  digitalWrite(PIN_LED3, LOW);
  digitalWrite(PIN_LED4, LOW);

  // --- WiFi ---
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.printf("Connecting to WiFi '%s'...\n", WIFI_SSID);

}

// ╔══════════════════════════════════════════════════════════╗
// ║  MAIN LOOP                                              ║
// ╚══════════════════════════════════════════════════════════╝

void loop() {

  // ── [1] WiFi → LED1 ─────────────────────────────────────
  if (WiFi.status() != WL_CONNECTED) {
    // WiFi dropped while connected → clean up
    if (serverConnected) disconnectFromServer();

    // Blink LED1 while connecting
    if (millis() - lastBlink > 500) {
      led1Blink = !led1Blink;
      digitalWrite(PIN_LED1, led1Blink);
      lastBlink = millis();
    }
    delay(100);
    return;
  }

  // WiFi connected → LED1 solid ON
  digitalWrite(PIN_LED1, HIGH);

  static bool ipPrinted = false;
  if (!ipPrinted) {
    Serial.printf("WiFi connected! IP: %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("Server target: %s:%d\n", SERVER_IP, SERVER_PORT);
    Serial.println("Press SW1 to connect to server...");

    if (influxClient.validateConnection()) {
      Serial.println("InfluxDB connected OK");
    } else {
      Serial.printf("InfluxDB error: %s\n", influxClient.getLastErrorMessage().c_str());
    }
    ipPrinted = true;
  }

  // ── [2] sw1 → Connect to Server ────────────────────────
  if (!serverConnected && digitalRead(PIN_SW1) == LOW) {
    delay(50);  // debounce
    if (digitalRead(PIN_SW1) == LOW) {
      connectToServer();
      while (digitalRead(PIN_SW1) == LOW) delay(10);  // wait release
    }
  }

  // ── Handle connected state ──────────────────────────────
  if (serverConnected) {

    // Check if server still alive
    if (!tcpClient.connected()) {
      disconnectFromServer();
      return;
    }

    // --- Check for unsolicited messages (DISCONNECT) ---
    while (tcpClient.available()) {
      String msg = tcpClient.readStringUntil('\n');
      msg.trim();

      if (msg == "DISCONNECT") {
        Serial.println("[CONN] Server requested disconnect");
        disconnectFromServer();
        return;
      }
      // อาจเป็น response จาก QUERY ที่ค้างอยู่
      processResponse(msg);
    }

    // --- [6] Every 3 seconds → send QUERY ---
    if (millis() - lastQuery >= 3000) {
      lastQuery = millis();  // reset timer BEFORE blocking wait

      tcpClient.println("QUERY");
      Serial.println("[QUERY] Sent to server");

      // Wait for response (max 2 seconds)
      unsigned long timeout = millis();
      while (!tcpClient.available() && millis() - timeout < 2000) {
        delay(10);
      }

      if (tcpClient.available()) {
        String response = tcpClient.readStringUntil('\n');
        response.trim();

        if (response == "DISCONNECT") {
          disconnectFromServer();
          return;
        }
        processResponse(response);
      } else {
        Serial.println("[QUERY] No response (timeout)");
      }
    }

    // --- [7] sw4 → disconnect ---
    if (digitalRead(PIN_SW4) == LOW) {
      delay(50);  // debounce
      if (digitalRead(PIN_SW4) == LOW) {
        Serial.println("[CONN] sw4 pressed → disconnecting");
        tcpClient.println("DISCONNECT");
        disconnectFromServer();
        while (digitalRead(PIN_SW4) == LOW) delay(10);  // wait release
        return;
      }
    }

  } else {
    // ── [4][8] Not connected → LED2, LED3, LED4 OFF ──────
    digitalWrite(PIN_LED2, LOW);
    digitalWrite(PIN_LED3, LOW);
    digitalWrite(PIN_LED4, LOW);
  }

  delay(50);
}

// ╔══════════════════════════════════════════════════════════╗
// ║  CONNECT TO SERVER (ข้อ 2, 3)                            ║
// ╚══════════════════════════════════════════════════════════╝

void connectToServer() {
  Serial.printf("Connecting to server %s:%d...\n", SERVER_IP, SERVER_PORT);

  if (!tcpClient.connect(SERVER_IP, SERVER_PORT)) {
    Serial.println("[CONN] Connection FAILED!");
    return;
  }

  // Wait for "ok" from server (max 3 seconds)
  unsigned long timeout = millis();
  while (!tcpClient.available() && millis() - timeout < 3000) {
    delay(10);
  }

  if (tcpClient.available()) {
    String response = tcpClient.readStringUntil('\n');
    response.trim();

    if (response == "ok") {
      serverConnected = true;
      lastQuery = millis();  // reset query timer

      // [3] LED2 ON
      digitalWrite(PIN_LED2, HIGH);
      Serial.println("[CONN] Connected! Received 'ok' → LED2 ON");
    } else {
      Serial.printf("[CONN] Unexpected response: '%s'\n", response.c_str());
      tcpClient.stop();
    }
  } else {
    Serial.println("[CONN] No response from server (timeout)");
    tcpClient.stop();
  }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  PROCESS QUERY RESPONSE (ข้อ 6)                          ║
// ╚══════════════════════════════════════════════════════════╝

void processResponse(String msg) {
  int colonIdx = msg.indexOf(':');
  if (colonIdx <= 0) return;  // invalid

  String type  = msg.substring(0, colonIdx);
  float  value = msg.substring(colonIdx + 1).toFloat();

  Serial.printf("[RECV] %s = %.1f%%\n", type.c_str(), value);

  if (type == "VR1") {
    // VR1 สูงกว่า (diff > 5%) → LED3 ติด, LED4 ดับ
    digitalWrite(PIN_LED3, HIGH);
    digitalWrite(PIN_LED4, LOW);
    Serial.printf("  → VR1 dominant (%.1f%%) → LED3 ON\n", value);

  } else if (type == "VR2") {
    // VR2 สูงกว่า (diff > 5%) → LED4 ติด, LED3 ดับ
    digitalWrite(PIN_LED3, LOW);
    digitalWrite(PIN_LED4, HIGH);
    Serial.printf("  → VR2 dominant (%.1f%%) → LED4 ON\n", value);

  } else if (type == "AVG") {
    // ผลต่าง <= 5% → LED3 + LED4 ติดทั้งคู่
    digitalWrite(PIN_LED3, HIGH);
    digitalWrite(PIN_LED4, HIGH);
    Serial.printf("  → VR1 ≈ VR2, average (%.1f%%) → LED3+LED4 ON\n", value);
  }

  // Log to InfluxDB
  sensorData.clearFields();
  sensorData.addField("response_type", type);
  sensorData.addField("vr_value", value);

  if (influxClient.writePoint(sensorData)) {
    Serial.println("  → [INFLUX] Client data written");
  } else {
    Serial.printf("  → [INFLUX] Write error: %s\n", influxClient.getLastErrorMessage().c_str());
  }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  DISCONNECT (ข้อ 4, 7, 8)                                ║
// ╚══════════════════════════════════════════════════════════╝

void disconnectFromServer() {
  tcpClient.stop();
  serverConnected = false;

  // [4][8] ดับ LED2, LED3, LED4
  digitalWrite(PIN_LED2, LOW);
  digitalWrite(PIN_LED3, LOW);
  digitalWrite(PIN_LED4, LOW);

  Serial.println("[CONN] Disconnected → LED2, LED3, LED4 OFF");
  Serial.println("Press SW1 to reconnect...");
}
