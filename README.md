# ESP32 Client-Server TCP — Auto-Deploy System

ระบบสื่อสารข้อมูลระหว่าง Client-Server ผ่าน WiFi + TCP พร้อม Auto-Deploy ผ่าน GitHub Actions

```
Programmer (เขียนโค้ด)  →  GitHub  →  Runner (ESP32 เสียบอยู่)  →  Upload อัตโนมัติ
```

---

## Quick Start — Arduino IDE

### 1. เพิ่ม ESP32 Board

**File → Preferences → Additional boards manager URLs** วางลิ้งค์นี้:

```
https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
```

จากนั้น **Tools → Board → Boards Manager** → พิมพ์ `esp32` → **Install**

### 2. ติดตั้ง Library

**Sketch → Include Library → Manage Libraries** → พิมพ์ `ESP8266 Influxdb` → **Install**

### 3. Download โค้ด

| ไฟล์ | ลิ้งค์ Raw (Ctrl+A copy ทั้งหมด) |
|------|------|
| **Server** | [server.ino](https://raw.githubusercontent.com/xjanova/Ardreno111/main/sketches/server/server.ino) |
| **Client** | [client.ino](https://raw.githubusercontent.com/xjanova/Ardreno111/main/sketches/client/client.ino) |

หรือ clone ทั้ง repo:

```bash
git clone https://github.com/xjanova/Ardreno111.git
```

---

## Configuration — สิ่งที่ต้องแก้ก่อน Upload

### WiFi (แก้ทั้ง server.ino และ client.ino)

```cpp
const char* WIFI_SSID     = "ชื่อ WiFi";        // ← แก้ตรงนี้
const char* WIFI_PASSWORD = "รหัส WiFi";         // ← แก้ตรงนี้
```

### Server IP (แก้เฉพาะ client.ino)

```cpp
const char* SERVER_IP = "192.168.x.x";           // ← ใส่ IP ของ Server
```

> วิธีหา IP: Upload server.ino ก่อน → เปิด Serial Monitor (115200) → จะเห็น `WiFi connected! IP: 192.168.x.x`

### InfluxDB (แก้ทั้ง 2 ไฟล์ — ถ้ายังไม่มี InfluxDB ข้ามได้ โค้ดทำงานปกติ)

```cpp
#define INFLUXDB_URL    "http://192.168.x.x:8086" // ← IP ของ InfluxDB server
#define INFLUXDB_TOKEN  "your-token"               // ← Token
#define INFLUXDB_ORG    "your-org"                 // ← Organization
#define INFLUXDB_BUCKET "your-bucket"              // ← Bucket name
```

### Pin Mapping (แก้ถ้าไม่ตรงกับบอร์ด)

```cpp
#define PIN_LED1  23    // ← WiFi status
#define PIN_LED2  22    // ← TCP connection
#define PIN_LED3  21    // ← Server: VR1 PWM / Client: VR indicator
#define PIN_LED4  19    // ← Server: VR2 PWM / Client: VR indicator
#define PIN_SW1   13    // ← Client: connect button (KEY1)
#define PIN_SW4   16    // ← Both: disconnect button (KEY4)
#define PIN_VR1   34    // ← Server: potentiometer 1
#define PIN_VR2   35    // ← Server: potentiometer 2
```

**วิธีหาเลข pin:** ดูตัวเลขบนแผงวงจร (silkscreen) ใกล้ LED/ปุ่ม/VR แล้วจับคู่กับ GPIO number

---

## Upload — ขั้นตอน

| ตั้งค่า Arduino IDE | ค่า |
|---------------------|-----|
| **Tools → Board** | ESP32 Dev Module |
| **Tools → Upload Speed** | 115200 |
| **Tools → Port** | COMx (port ที่เสียบ) |

### ลำดับ Upload

1. เสียบ **ESP32 ตัวที่ 1** → Upload `server.ino` → เปิด Serial Monitor → **จด IP**
2. แก้ `SERVER_IP` ใน client.ino ให้ตรง
3. เสียบ **ESP32 ตัวที่ 2** → Upload `client.ino`
4. เปิด Serial Monitor ทั้ง 2 ตัว (115200 baud)

> ถ้า Upload ไม่ขึ้น: กดปุ่ม **BOOT** บน ESP32 ค้างไว้ตอนเห็น `Connecting...` แล้วปล่อย

---

## ทดสอบ

| ขั้นตอน | ทำ | ผลที่ควรได้ |
|---------|-----|------------|
| 1 | เปิดทั้ง 2 บอร์ด | LED1 กระพริบ (กำลังเชื่อม WiFi) |
| 2 | รอ WiFi | LED1 ติดค้าง ทั้ง 2 บอร์ด |
| 3 | กด SW1 ที่ Client | LED2 ติด ทั้ง 2 บอร์ด |
| 4 | หมุน VR1 ที่ Server | LED3 สว่างตาม + Serial แสดง VR1% |
| 5 | หมุน VR2 ที่ Server | LED4 สว่างตาม + Serial แสดง VR2% |
| 6 | ตั้ง VR1 สูงกว่า VR2 มาก | Client: LED3 ติด LED4 ดับ (รอ 3 วินาที) |
| 7 | ตั้ง VR2 สูงกว่า VR1 มาก | Client: LED4 ติด LED3 ดับ |
| 8 | ตั้ง VR1 ใกล้เคียง VR2 | Client: LED3+LED4 ติดทั้งคู่ |
| 9 | กด SW4 ฝั่งใดก็ได้ | LED2, LED3, LED4 ดับ ทั้ง 2 บอร์ด |

---

## Scoring — เช็คลิสต์ 100 คะแนน

- [ ] **(15)** WiFi + LED1 กระพริบตอนเชื่อม / ติดค้างเมื่อเชื่อมแล้ว
- [ ] **(10)** กด SW1 → Client เชื่อมต่อ Server
- [ ] **(5)** LED2 ติดทั้งคู่ + Server ส่ง "ok"
- [ ] **(5)** LED2 ดับเมื่อ disconnect
- [ ] **(15)** Server: VR1%, VR2% แสดง Serial + LED3/LED4 สว่างตาม VR + InfluxDB ทุก 2s
- [ ] **(10)** diff > 5% + VR1 สูงกว่า → Client LED3 ติด
- [ ] **(10)** diff > 5% + VR2 สูงกว่า → Client LED4 ติด
- [ ] **(10)** diff ≤ 5% → Client LED3+LED4 ติด
- [ ] **(10)** Client บันทึก InfluxDB
- [ ] **(5)** SW4 disconnect ได้ทั้ง 2 ฝั่ง
- [ ] **(5)** LED3+LED4 ดับทั้งคู่เมื่อ disconnect

---

## Troubleshooting

| ปัญหา | วิธีแก้ |
|--------|---------|
| LED1 กระพริบไม่หยุด | ชื่อ/รหัส WiFi ผิด หรือ WiFi ไม่อยู่ในระยะ |
| กด SW1 แล้วไม่เชื่อมต่อ | `SERVER_IP` ไม่ตรง — เช็ค Serial Monitor ของ Server |
| "Connection FAILED" | Server ยังไม่เปิด หรือ Firewall บล็อค port 8080 |
| VR แสดง 0% ตลอด | เลข pin VR ไม่ตรง — เช็คบอร์ด |
| LED3/LED4 ไม่ติด | เลข pin LED ไม่ตรง — เช็คบอร์ด |
| InfluxDB error | URL/Token ผิด — ข้ามได้ โค้ดทำงานปกติโดยไม่มี InfluxDB |
| Upload ไม่ขึ้น | กดปุ่ม BOOT ค้างระหว่าง Upload / ลองเปลี่ยนสาย USB |
| Serial Monitor เป็นภาษาต่างดาว | ตั้ง Baud Rate เป็น **115200** |

---

## Auto-Deploy System (สำหรับ Remote Development)

ถ้าต้องการให้ push โค้ดแล้ว Arduino อัพเดทอัตโนมัติ:

### วิศวกรฝั่งที่มีบอร์ด — รันครั้งเดียว:

```powershell
irm https://raw.githubusercontent.com/xjanova/Ardreno111/main/bootstrap.ps1 | iex
```

### Programmer — ใช้งานทุกวัน:

```bash
# แก้โค้ด → push → Arduino อัพเดทเอง
git add . && git commit -m "update sketch" && git push
```

### ไฟล์ในระบบ

| ไฟล์ | หน้าที่ |
|------|--------|
| `sketches/server/server.ino` | โค้ด TCP Server |
| `sketches/client/client.ino` | โค้ด TCP Client |
| `sketches/blink/blink.ino` | ทดสอบระบบ deploy |
| `install_runner.ps1` | ติดตั้ง Runner + Arduino CLI (ครั้งเดียว) |
| `bootstrap.ps1` | ติดตั้ง Git + clone + รัน installer |
| `deploy.ps1` | Deploy มือ (auto-detect board) |
| `check_deploy.ps1` | เช็ค status workflow |
| `.github/workflows/arduino-deploy.yml` | GitHub Actions workflow |
