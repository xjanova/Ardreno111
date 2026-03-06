/*
 * ===== SERVER.INO =====
 * TCP Server — ESP32 Client-Server VR Communication
 *
 * Scoring covered:
 *   1. WiFi + LED1 blink/solid             (15 pts)
 *   3. LED2 ON when client connects + "ok"  (5 pts)
 *   4. LED2 OFF when disconnected           (5 pts)
 *   5. VR1%, VR2% Serial + LED3/LED4 PWM + InfluxDB every 2s  (15 pts)
 *   6. Handle QUERY → compare VR1 vs VR2 → respond  (30 pts)
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

// WiFi
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// TCP Server port
#define TCP_PORT 8080

// InfluxDB (InfluxDB 2.x)
#define INFLUXDB_URL    "http://YOUR_INFLUXDB_IP:8086"
#define INFLUXDB_TOKEN  "YOUR_TOKEN"
#define INFLUXDB_ORG    "YOUR_ORG"
#define INFLUXDB_BUCKET "YOUR_BUCKET"

// ╔══════════════════════════════════════════════════════════╗
// ║  PIN MAPPING — ตรวจสอบให้ตรงกับบอร์ดของคุณ                    ║
// ╚══════════════════════════════════════════════════════════╝
//
//  Board layout (ดูจากของจริง):
//    Potentiometers: VR1, VR2, VR3 (top)
//    LEDs: LED1, LED2, LED3, LED4 (middle)
//    Buttons: KEY1(sw1), KEY2(sw2), KEY3(sw3), KEY4(sw4) (right)
//

#define PIN_LED1  23      // WiFi status
#define PIN_LED2  22      // TCP connection status
#define PIN_LED3  21      // VR1 brightness (PWM)
#define PIN_LED4  19      // VR2 brightness (PWM)

#define PIN_SW4   16      // Disconnect button (KEY4)

#define PIN_VR1   34      // Potentiometer 1 (ADC1 — safe with WiFi)
#define PIN_VR2   35      // Potentiometer 2 (ADC1 — safe with WiFi)

// PWM config
#define PWM_FREQ       5000
#define PWM_RESOLUTION 8      // 0-255

// ╔══════════════════════════════════════════════════════════╗
// ║  GLOBALS                                                ║
// ╚══════════════════════════════════════════════════════════╝

WiFiServer tcpServer(TCP_PORT);
WiFiClient tcpClient;

InfluxDBClient influxClient(INFLUXDB_URL, INFLUXDB_ORG, INFLUXDB_BUCKET, INFLUXDB_TOKEN);
Point sensorData("server_vr");

bool clientConnected     = false;
unsigned long lastInflux = 0;
unsigned long lastPrint  = 0;
unsigned long lastBlink  = 0;
bool led1Blink           = false;

// ╔══════════════════════════════════════════════════════════╗
// ║  SETUP                                                  ║
// ╚══════════════════════════════════════════════════════════╝

void setup() {
  Serial.begin(115200);
  Serial.println("\n===== SERVER STARTING =====");

  // --- Pins ---
  pinMode(PIN_LED1, OUTPUT);
  pinMode(PIN_LED2, OUTPUT);
  pinMode(PIN_SW4, INPUT_PULLUP);

  // PWM for LED3, LED4 (brightness control) — ESP32 Core 3.x API
  ledcAttach(PIN_LED3, PWM_FREQ, PWM_RESOLUTION);
  ledcAttach(PIN_LED4, PWM_FREQ, PWM_RESOLUTION);

  // All LEDs off
  digitalWrite(PIN_LED1, LOW);
  digitalWrite(PIN_LED2, LOW);
  ledcWrite(PIN_LED3, 0);
  ledcWrite(PIN_LED4, 0);

  // --- WiFi ---
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.printf("Connecting to WiFi '%s'...\n", WIFI_SSID);

  // --- TCP Server ---
  tcpServer.begin();
  tcpServer.setNoDelay(true);

}

// ╔══════════════════════════════════════════════════════════╗
// ║  MAIN LOOP                                              ║
// ╚══════════════════════════════════════════════════════════╝

void loop() {

  // ── [1] WiFi → LED1 ─────────────────────────────────────
  if (WiFi.status() != WL_CONNECTED) {
    // WiFi dropped while client was connected → clean up
    if (clientConnected) disconnectClient();

    // Blink LED1 while connecting
    if (millis() - lastBlink > 500) {
      led1Blink = !led1Blink;
      digitalWrite(PIN_LED1, led1Blink);
      lastBlink = millis();
    }
    delay(100);
    return;   // ไม่ทำอะไรจนกว่า WiFi จะเชื่อมต่อ
  }

  // WiFi connected → LED1 solid ON
  digitalWrite(PIN_LED1, HIGH);

  // Print IP once + validate InfluxDB after WiFi is up
  static bool ipPrinted = false;
  if (!ipPrinted) {
    Serial.printf("WiFi connected! IP: %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("TCP Server listening on port %d\n", TCP_PORT);

    if (influxClient.validateConnection()) {
      Serial.println("InfluxDB connected OK");
    } else {
      Serial.printf("InfluxDB error: %s\n", influxClient.getLastErrorMessage().c_str());
    }
    ipPrinted = true;
  }

  // ── [3] Accept new client ───────────────────────────────
  if (!clientConnected) {
    WiFiClient newClient = tcpServer.available();
    if (newClient && newClient.connected()) {
      tcpClient = newClient;
      clientConnected = true;

      // LED2 ON
      digitalWrite(PIN_LED2, HIGH);

      // Send "ok" to client
      tcpClient.println("ok");
      Serial.println("[CONN] Client connected → LED2 ON, sent 'ok'");
    }
  }

  // ── Handle connected client ─────────────────────────────
  if (clientConnected) {

    // Check if client still alive
    if (!tcpClient.connected()) {
      disconnectClient();
      return;
    }

    // --- Read incoming data from client ---
    if (tcpClient.available()) {
      String msg = tcpClient.readStringUntil('\n');
      msg.trim();

      if (msg == "QUERY") {
        handleQuery();
      } else if (msg == "DISCONNECT") {
        Serial.println("[CONN] Client requested disconnect");
        tcpClient.println("DISCONNECT");
        disconnectClient();
        return;
      }
    }

    // --- [7] sw4 → disconnect ---
    if (digitalRead(PIN_SW4) == LOW) {
      delay(50);  // debounce
      if (digitalRead(PIN_SW4) == LOW) {
        Serial.println("[CONN] sw4 pressed → disconnecting");
        tcpClient.println("DISCONNECT");
        disconnectClient();
        while (digitalRead(PIN_SW4) == LOW) delay(10);  // wait release
        return;
      }
    }

    // --- [5] Read VR1, VR2 → Serial + LED3/LED4 + InfluxDB ---
    int vr1Raw = analogRead(PIN_VR1);
    int vr2Raw = analogRead(PIN_VR2);
    float vr1Pct = (vr1Raw / 4095.0) * 100.0;
    float vr2Pct = (vr2Raw / 4095.0) * 100.0;

    // Serial output (ทุก 500ms เพื่อไม่ให้ spam)
    if (millis() - lastPrint >= 500) {
      Serial.printf("VR1: %.1f%%  |  VR2: %.1f%%\n", vr1Pct, vr2Pct);
      lastPrint = millis();
    }

    // LED3 brightness = VR1, LED4 brightness = VR2
    ledcWrite(PIN_LED3, map(vr1Raw, 0, 4095, 0, 255));
    ledcWrite(PIN_LED4, map(vr2Raw, 0, 4095, 0, 255));

    // InfluxDB every 2 seconds
    if (millis() - lastInflux >= 2000) {
      sensorData.clearFields();
      sensorData.addField("vr1_percent", vr1Pct);
      sensorData.addField("vr2_percent", vr2Pct);

      if (influxClient.writePoint(sensorData)) {
        Serial.println("[INFLUX] Server VR data written");
      } else {
        Serial.printf("[INFLUX] Write error: %s\n", influxClient.getLastErrorMessage().c_str());
      }
      lastInflux = millis();
    }

  } else {
    // ── [4][8] Not connected → LED2, LED3, LED4 OFF ──────
    digitalWrite(PIN_LED2, LOW);
    ledcWrite(PIN_LED3, 0);
    ledcWrite(PIN_LED4, 0);
  }

  delay(50);
}

// ╔══════════════════════════════════════════════════════════╗
// ║  HANDLE QUERY (ข้อ 6)                                    ║
// ╚══════════════════════════════════════════════════════════╝

void handleQuery() {
  int vr1Raw = analogRead(PIN_VR1);
  int vr2Raw = analogRead(PIN_VR2);
  float vr1Pct = (vr1Raw / 4095.0) * 100.0;
  float vr2Pct = (vr2Raw / 4095.0) * 100.0;
  float diff   = abs(vr1Pct - vr2Pct);

  if (diff > 5.0 && vr1Pct > vr2Pct) {
    // VR1 สูงกว่า → ส่ง VR1% → Client LED3 ติด
    tcpClient.printf("VR1:%.1f\n", vr1Pct);
    Serial.printf("[QUERY] VR1 > VR2 (diff=%.1f%%) → sent VR1:%.1f\n", diff, vr1Pct);

  } else if (diff > 5.0 && vr2Pct > vr1Pct) {
    // VR2 สูงกว่า → ส่ง VR2% → Client LED4 ติด
    tcpClient.printf("VR2:%.1f\n", vr2Pct);
    Serial.printf("[QUERY] VR2 > VR1 (diff=%.1f%%) → sent VR2:%.1f\n", diff, vr2Pct);

  } else {
    // ผลต่าง <= 5% → ส่งค่าเฉลี่ย → Client LED3+LED4 ติด
    float avg = (vr1Pct + vr2Pct) / 2.0;
    tcpClient.printf("AVG:%.1f\n", avg);
    Serial.printf("[QUERY] VR1≈VR2 (diff=%.1f%%) → sent AVG:%.1f\n", diff, avg);
  }
}

// ╔══════════════════════════════════════════════════════════╗
// ║  DISCONNECT                                             ║
// ╚══════════════════════════════════════════════════════════╝

void disconnectClient() {
  tcpClient.stop();
  clientConnected = false;

  // [4][8] ดับ LED2, LED3, LED4
  digitalWrite(PIN_LED2, LOW);
  ledcWrite(PIN_LED3, 0);
  ledcWrite(PIN_LED4, 0);

  Serial.println("[CONN] Disconnected → LED2, LED3, LED4 OFF");
}
