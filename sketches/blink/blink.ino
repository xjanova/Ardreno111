/*
 * blink.ino — Test sketch for Arduino Auto-Deploy System
 *
 * LED blinks on built-in LED.
 * ESP32: GPIO 2, Arduino Uno: pin 13
 */

#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(9600);
  Serial.println("Auto-Deploy OK — Blink running!");
}

void loop() {
  digitalWrite(LED_BUILTIN, HIGH);
  delay(1000);
  digitalWrite(LED_BUILTIN, LOW);
  delay(1000);
}
